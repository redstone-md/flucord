import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// FLUCORD-97: a bio draws like a chat message, and the card's text can be
// selected and copied.

const _messageId = '900000000000000071';
const _profilePath = '/api/v9/users/${SessionHarness.friendId}/profile';

final _card = find.byKey(const ValueKey('profile-card'));
final _bio = find.byKey(const ValueKey('profile-card-bio'));

void Function(FakeDiscordTransport) _bioRoute(String bio) =>
    (transport) => transport.on(
      'GET',
      _profilePath,
      (_) => jsonResponse({
        'user': {'id': SessionHarness.friendId, 'username': 'friend'},
        'user_profile': {'bio': bio},
      }),
    );

/// The friend as a message author, with their name glowing in neon.
const _neonAuthor = {
  'id': SessionHarness.friendId,
  'username': 'friend',
  'global_name': 'Friend',
  'display_name_styles': {
    'colors': [0xff5555],
    'font_id': 11,
    'effect_id': 3,
  },
};

/// Opens the friend's card from a message of theirs, in the server or, with
/// [inDm], in their DM.
Future<void> _openCard(
  WidgetTester tester,
  SessionHarness session, {
  bool inDm = false,
  Map<String, Object?>? author,
}) async {
  final channelId = inDm
      ? SessionHarness.dmChannelId
      : SessionHarness.channelId;
  await session.openChannel(
    channelId,
    space: inDm ? 'direct-messages' : SessionHarness.guildId,
  );
  await session.dispatch(
    'MESSAGE_CREATE',
    rawMessage(
      id: _messageId,
      channelId: channelId,
      guildId: inDm ? null : SessionHarness.guildId,
      authorId: SessionHarness.friendId,
      content: 'hello',
    )..addAll({'author': ?author}),
  );
  await tester.tap(
    find.descendant(
      of: session.messageRow(_messageId),
      matching: find.byKey(const ValueKey('message-author-name')),
    ),
  );
  await session.settle();
  expect(_card, findsOneWidget);
}

Finder _inBio(String text) => find.descendant(
  of: _bio,
  matching: find.textContaining(text, findRichText: true),
);

/// What the app put on the clipboard, once a test calls [_watchClipboard].
String? _copied;

void _watchClipboard(WidgetTester tester) {
  _copied = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        _copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

Future<String?> _copyAll(WidgetTester tester, Finder within) async {
  _watchClipboard(tester);
  final region = find
      .descendant(of: within, matching: find.byType(SelectableRegion))
      .first;
  tester
      .state<SelectableRegionState>(region)
      .selectAll(SelectionChangedCause.keyboard);
  await tester.pump();
  // What Ctrl+C asks of the selection.
  Actions.invoke(
    tester.element(
      find.descendant(of: region, matching: find.byType(Text)).first,
    ),
    CopySelectionTextIntent.copy,
  );
  await tester.pump();
  return _copied;
}

void main() {
  testSession(
    'a bio draws markdown and its links open through the card',
    (tester, session) async {
      await _openCard(tester, session);

      expect(_inBio('**'), findsNothing, reason: 'markers are not drawn');
      expect(_inBio('Bold'), findsOneWidget);
      expect(_inBio('site'), findsOneWidget);
      expect(_inBio('[site]'), findsNothing);

      // A link leaving Discord asks first, as it does in a message.
      await tester.tapOnText(find.textRange.ofSubstring('site'));
      await session.settle();
      await tester.tap(find.byKey(const ValueKey('leaving-site-visit')));
      await session.settle();
      await tester.tapOnText(
        find.textRange.ofSubstring('https://example.com/a'),
      );
      await session.settle();
      await tester.tap(find.byKey(const ValueKey('leaving-site-visit')));
      await session.settle();

      expect(session.openedLinks, [
        Uri.parse('https://site.example/b'),
        Uri.parse('https://example.com/a'),
      ]);
    },
    routes: _bioRoute(
      '**Bold** and *soft*. See [site](https://site.example/b) or '
      'https://example.com/a',
    ),
  );

  testSession(
    'a mention in a bio reads the name, as chat does',
    (tester, session) async {
      await _openCard(tester, session);

      expect(_inBio('@user-${SessionHarness.friendId}'), findsOneWidget);
      expect(_inBio('<@'), findsNothing);
    },
    routes: _bioRoute('Made by <@${SessionHarness.friendId}>'),
  );

  testSession(
    'a long bio is cut with View full bio, which shows it whole',
    (tester, session) async {
      await _openCard(tester, session);
      expect(
        find.byKey(const ValueKey('profile-card-view-bio')),
        findsOneWidget,
      );
      expect(tester.getSize(_bio).height, lessThanOrEqualTo(3 * 18 + 0.5));

      await tester.tap(find.byKey(const ValueKey('profile-card-view-bio')));
      await session.settle();

      final full = find.byKey(const ValueKey('full-profile-bio'));
      expect(
        find.descendant(
          of: full,
          matching: find.textContaining('line 10', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: full,
          matching: find.textContaining('**', findRichText: true),
        ),
        findsNothing,
      );
    },
    routes: _bioRoute(
      [for (var line = 1; line <= 10; line++) '**line $line**'].join('\n'),
    ),
  );

  testSession('a short bio has no View full bio', (tester, session) async {
    await _openCard(tester, session);

    expect(find.byKey(const ValueKey('profile-card-view-bio')), findsNothing);
  }, routes: _bioRoute('Just one line'));

  testSession(
    'the card text copies the name once, the handle, and the bio',
    (tester, session) async {
      await _openCard(tester, session, inDm: true, author: _neonAuthor);

      final copied = await _copyAll(tester, _card);

      // ignore: avoid_print
      print('COPIED<$copied>');
      expect(copied, isNotNull);
      expect(
        'Friend'.allMatches(copied!.replaceAll('friend', '')),
        hasLength(1),
      );
      expect(copied, contains('friend'));
      expect(copied, contains('Likes neon'));
    },
    routes: _bioRoute('Likes neon'),
  );

  testSession('a click on the name still opens the full profile', (
    tester,
    session,
  ) async {
    await _openCard(tester, session);

    await tester.tap(find.byKey(const ValueKey('profile-card-name')));
    await session.settle();

    expect(find.byKey(const ValueKey('full-profile')), findsOneWidget);
  }, routes: _bioRoute('Hello'));
}
