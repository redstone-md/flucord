import 'package:flucord/src/domain/monogram.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/focus_traversal.dart';
import 'support/session_harness.dart';

// The Friends page (FLUCORD-56): the Friends row at the top of the DM list
// opens it in the canvas, beside the DM list and the Active now column.

Map<String, Object?> _ready() =>
    SessionHarness.defaultReady()
      ..['relationships'] = [
        {
          'id': SessionHarness.friendId,
          'type': 1,
          'user': {
            'id': SessionHarness.friendId,
            'username': 'friend',
            'global_name': 'Friend',
          },
        },
        // A friend who shares no server or DM with the account, so the
        // workspace holds no member record for them.
        {
          'id': _strangerId,
          'type': 1,
          'user': {
            'id': _strangerId,
            'username': 'faraway',
            'global_name': 'Far Away',
          },
        },
      ];

const _strangerId = '777777777777777777';

final _friendsRow = find.byKey(const ValueKey('toggle-friends'));
final _page = find.byKey(const ValueKey('friends-panel'));
final _dmRow = find.byKey(
  const ValueKey('channel-${SessionHarness.dmChannelId}'),
);

/// Whether [row] announces itself as selected. The key sits outside the
/// row's own semantics, so the first [Semantics] inside it answers.
bool _selected(WidgetTester tester, Finder row) =>
    isSemantics(isSelected: true).matches(
      tester.getSemantics(
        find.descendant(of: row, matching: find.byType(Semantics)).first,
      ),
      <Object?, Object?>{},
    );

Future<void> _openDirectMessages(
  WidgetTester tester,
  SessionHarness session,
) async {
  await tester.tap(find.byKey(const ValueKey('space-direct-messages')));
  await session.settle();
}

void main() {
  testSession(
    'the Friends row is reached by keyboard and opens the page',
    (tester, session) async {
      await _openDirectMessages(tester, session);
      expect(_page, findsNothing);

      await tabTo(tester, _friendsRow);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await session.settle();

      expect(_page, findsOneWidget);
      expect(_selected(tester, _friendsRow), isTrue);
      // The page takes the canvas. The DM list stays in the sidebar, and
      // Active now sits beside the page.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('channel-sidebar')),
          matching: _page,
        ),
        findsNothing,
      );
      expect(_dmRow, findsOneWidget);
      expect(find.text('Active now'), findsOneWidget);
    },
    ready: _ready(),
    platform: TargetPlatform.windows,
  );

  testSession('opening a DM from the list leaves the page', (
    tester,
    session,
  ) async {
    await _openDirectMessages(tester, session);
    await tester.tap(_friendsRow);
    await session.settle();

    await tester.tap(_dmRow);
    await session.settle();

    expect(_page, findsNothing);
    expect(_selected(tester, _friendsRow), isFalse);
    expect(_selected(tester, _dmRow), isTrue);
  }, ready: _ready());

  testSession('a friend row opens the profile card beside the name', (
    tester,
    session,
  ) async {
    await _openDirectMessages(tester, session);
    await tester.tap(_friendsRow);
    await session.settle();
    await tester.tap(find.byKey(const ValueKey('friends-tab-all')));
    await session.settle();

    for (final (id, name) in [
      (SessionHarness.friendId, 'Friend'),
      (_strangerId, 'Far Away'),
    ]) {
      final trigger = find.byKey(ValueKey('friend-profile-$id'));
      await tester.tap(trigger);
      await session.settle();

      final card = find.byKey(const ValueKey('profile-card'));
      expect(
        find.descendant(of: card, matching: find.text(name)),
        findsWidgets,
      );
      // Beside the avatar and name, top level with them.
      expect(
        tester.getTopLeft(card).dx,
        greaterThanOrEqualTo(tester.getTopRight(trigger).dx),
      );
      expect(tester.getTopLeft(card).dy, tester.getTopLeft(trigger).dy);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await session.settle();
      expect(card, findsNothing);
    }
  }, ready: _ready());

  testSession('a friend outside the workspace takes the colour of their id', (
    tester,
    session,
  ) async {
    await _openDirectMessages(tester, session);
    await tester.tap(_friendsRow);
    await session.settle();
    await tester.tap(find.byKey(const ValueKey('friends-tab-all')));
    await session.settle();

    await tester.tap(find.byKey(const ValueKey('friend-profile-$_strangerId')));
    await session.settle();

    final banner = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('profile-card-banner')),
    );
    expect(banner.color, Color(monogramColorOf(_strangerId)));
  }, ready: _ready());

  testSession(
    'a friend row opens the DM with them',
    (tester, session) async {
      await _openDirectMessages(tester, session);
      await tester.tap(_friendsRow);
      await session.settle();
      await tester.tap(find.byKey(const ValueKey('friends-tab-all')));
      await session.settle();

      await tester.tap(
        find.byKey(const ValueKey('friend-message-${SessionHarness.friendId}')),
      );
      await session.settle();

      expect(_page, findsNothing);
      expect(_selected(tester, _dmRow), isTrue);
    },
    ready: _ready(),
    routes: _routeOpenDm,
  );
}

/// Discord answers with the DM the account already has with the friend.
void _routeOpenDm(FakeDiscordTransport transport) => transport.on(
  'POST',
  '/api/v9/users/@me/channels',
  (_) => jsonResponse({
    'id': SessionHarness.dmChannelId,
    'type': 1,
    'recipients': [
      {'id': SessionHarness.friendId},
    ],
  }),
);
