import 'package:flucord/src/presentation/widgets/chat_header.dart';
import 'package:flucord/src/presentation/widgets/member_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_font.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// A DM in direction B (FLUCORD-82): the header shows the person's avatar
// with a status dot, then their whole name, at the window size the app opens
// with; the history starts on the person.

const _name = 'Konstantin Konstantinopolsky';

const _friend = {
  'id': SessionHarness.friendId,
  'username': 'konstantin',
  'global_name': _name,
};

Map<String, Object?> _ready() {
  final ready = SessionHarness.defaultReady();
  ready['users'] = [_friend];
  return ready;
}

void main() {
  testSession(
    'a DM header shows the avatar and the whole name',
    (tester, session) async {
      await loadAppFont(tester);
      await session.openChannel(
        SessionHarness.dmChannelId,
        space: 'direct-messages',
      );

      final header = find.byType(ChatHeader);
      final avatar = find.descendant(
        of: header,
        matching: find.byType(MemberAvatar),
      );
      expect(tester.getSize(avatar), const Size.square(24));
      expect(
        find.descendant(
          of: avatar,
          matching: find.byKey(
            const ValueKey('member-presence-${SessionHarness.friendId}'),
          ),
        ),
        findsOneWidget,
      );

      final title = find.descendant(of: header, matching: find.text(_name));
      expect(
        tester.getRect(avatar).right,
        lessThan(tester.getRect(title).left),
      );
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
        reason: 'the whole name is drawn, not cut with an ellipsis',
      );
    },
    ready: _ready(),
    // The window the app opens with on Linux.
    size: const Size(1280, 720),
  );

  testSession(
    'a DM opens on the person, not on a channel heading',
    (tester, session) async {
      await session.openChannel(
        SessionHarness.dmChannelId,
        space: 'direct-messages',
      );

      const intro =
          'This is the beginning of your direct message history with $_name.';
      expect(find.text(intro), findsOneWidget);
      final avatar = find.ancestor(
        of: find.text(intro),
        matching: find.byType(Column),
      );
      expect(
        tester.getSize(
          find.descendant(
            of: avatar.first,
            matching: find.byType(MemberAvatar),
          ),
        ),
        const Size.square(80),
      );
      expect(find.text('# $_name'), findsNothing);
      expect(
        find.descendant(of: avatar.first, matching: find.text('konstantin')),
        findsOneWidget,
      );
    },
    ready: _ready(),
    routes: _oneMessageInTheDm,
  );

  testSession(
    'a DM shows who it is with in a profile panel beside it',
    (tester, session) async {
      await session.dispatch('GUILD_MEMBER_ADD', {
        'guild_id': SessionHarness.guildId,
        'roles': <Object?>[],
        'user': _friend,
      });
      await session.openChannel(
        SessionHarness.dmChannelId,
        space: 'direct-messages',
      );

      final panel = find.byKey(const ValueKey('dm-profile-panel'));
      Finder inPanel(Finder matching) =>
          find.descendant(of: panel, matching: matching);
      expect(tester.getSize(panel).width, 240);
      expect(
        tester.getSize(inPanel(find.byType(MemberAvatar))),
        const Size.square(64),
      );
      expect(inPanel(find.text(_name)), findsOneWidget);
      expect(inPanel(find.text('konstantin')), findsOneWidget);
      // The friend's id was minted in October 2015.
      expect(inPanel(find.text('Member since')), findsOneWidget);
      expect(inPanel(find.textContaining('2015')), findsOneWidget);
      expect(inPanel(find.text('Mutual servers 1')), findsOneWidget);
      expect(inPanel(find.text('The Forge')), findsOneWidget);

      await tester.tap(find.byTooltip('Hide user profile'));
      await session.settle();
      expect(panel, findsNothing);
    },
    ready: _ready(),
    size: const Size(1280, 720),
  );
}

/// The DM's whole history is one message, so it opens at its start.
void _oneMessageInTheDm(FakeDiscordTransport transport) => transport.on(
  'GET',
  '/api/v9/channels/${SessionHarness.dmChannelId}/messages',
  (_) => jsonResponse([
    {
      ...rawMessage(
        id: '400000000000000001',
        channelId: SessionHarness.dmChannelId,
        authorId: SessionHarness.friendId,
        content: 'hi',
      ),
      // The author as READY named them, so the message does not rename them.
      'author': _friend,
    },
  ]),
);
