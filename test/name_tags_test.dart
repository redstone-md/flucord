import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';
import 'package:flucord/src/presentation/widgets/name_tags.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';
import 'support/type_scale.dart';

const _botId = '100000000000000007';
const _botMessageId = '900000000000000021';
const _replyId = '900000000000000022';

const _clan = {
  'tag': 'CODE',
  'badge': null,
  'identity_guild_id': '200000000000000009',
  'identity_enabled': true,
};

Map<String, Object?> _fromBot() =>
    rawMessage(
        id: _botMessageId,
        channelId: SessionHarness.channelId,
        guildId: SessionHarness.guildId,
        authorId: _botId,
        content: 'beep',
      )
      ..['author'] = {
        'id': _botId,
        'username': 'Helper',
        'bot': true,
        'primary_guild': _clan,
      };

Finder _in(Finder row, Finder matching) =>
    find.descendant(of: row, matching: matching);

/// Bots carry an APP tag and clan members a clan chip, beside the name.
void main() {
  testSession('a row with both tags stays on the type scale', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('MESSAGE_CREATE', _fromBot());

    expect(find.text('APP'), findsWidgets);
    expect(find.text('CODE'), findsWidgets);
    expectTextOnTypeScale(tester);
  });

  testSession('a bot author shows the clan chip and APP beside the name', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('MESSAGE_CREATE', _fromBot());

    final row = session.messageRow(_botMessageId);
    final name = tester.getRect(_in(row, find.text('Helper')));
    final clan = tester.getRect(_in(row, find.byType(ClanTagChip)));
    final app = tester.getRect(_in(row, find.byType(AppTag)));

    expect(_in(row, find.text('CODE')), findsOneWidget);
    expect(_in(row, find.text('APP')), findsOneWidget);
    expect(clan.height, 16);
    expect(app.height, 15);
    expect(clan.left, greaterThan(name.right));
    expect(app.left, greaterThan(clan.right));
    expect(clan.center.dy, closeTo(name.center.dy, 0.5));
    expect(app.center.dy, closeTo(name.center.dy, 0.5));
  });

  testSession('a reply to a bot shows APP, without the clan chip', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('MESSAGE_CREATE', _fromBot());
    await session.dispatch(
      'MESSAGE_CREATE',
      rawMessage(
          id: _replyId,
          channelId: SessionHarness.channelId,
          guildId: SessionHarness.guildId,
          authorId: SessionHarness.friendId,
          content: 'thanks',
          timestamp: '2026-07-25T10:05:00+00:00',
        )
        ..['type'] = 19
        ..['message_reference'] = {'message_id': _botMessageId}
        ..['referenced_message'] = _fromBot(),
    );

    final reply = find.byKey(const ValueKey('message-reply-preview'));
    expect(_in(reply, find.text('APP')), findsOneWidget);
    expect(_in(reply, find.byType(ClanTagChip)), findsNothing);
  });

  testSession('a clan tag that arrives on a presence update shows', (
    tester,
    session,
  ) async {
    const messageId = '900000000000000023';
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch(
      'MESSAGE_CREATE',
      rawMessage(
        id: messageId,
        channelId: SessionHarness.channelId,
        guildId: SessionHarness.guildId,
        authorId: SessionHarness.friendId,
        content: 'hello',
      ),
    );
    final row = session.messageRow(messageId);
    expect(_in(row, find.byType(ClanTagChip)), findsNothing);

    await session.dispatch('PRESENCE_UPDATE', {
      'guild_id': SessionHarness.guildId,
      'status': 'online',
      'activities': <Object?>[],
      'user': {
        'id': SessionHarness.friendId,
        'username': 'user-${SessionHarness.friendId}',
        'primary_guild': _clan,
      },
    });
    expect(_in(row, find.text('CODE')), findsOneWidget);

    // Most presence updates name the user by id alone. That says nothing
    // about the tag, so it stays.
    await session.dispatch('PRESENCE_UPDATE', {
      'guild_id': SessionHarness.guildId,
      'status': 'idle',
      'activities': <Object?>[],
      'user': {'id': SessionHarness.friendId},
    });
    expect(_in(row, find.text('CODE')), findsOneWidget);
  });

  testWidgets('a bot in the member list shows the clan chip and APP', (
    tester,
  ) async {
    const bot = Member(
      id: _botId,
      displayName: 'Helper',
      initials: 'H',
      role: 'Member',
      presence: Presence.online,
      colorValue: 0xff665f82,
      spaceIds: {'guild-1'},
      isBot: true,
      clanTag: ClanTag(tag: 'CODE', guildId: 'guild-9'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: SizedBox()),
              MemberSidebar(
                members: const [bot],
                spaceId: 'guild-1',
                currentMemberId: 'me',
                onMessage: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    final row = find.byKey(const ValueKey('member-row-$_botId'));
    final name = tester.getRect(_in(row, find.text('Helper')));
    expect(_in(row, find.text('CODE')), findsOneWidget);
    expect(_in(row, find.text('APP')), findsOneWidget);
    expect(
      tester.getRect(_in(row, find.byType(ClanTagChip))).left,
      greaterThan(name.right),
    );
  });

  testWidgets('a person with no clan shows no tags', (tester) async {
    const person = Member(
      id: 'person-1',
      displayName: 'Mira',
      initials: 'M',
      role: 'Member',
      presence: Presence.online,
      colorValue: 0xff665f82,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: const Scaffold(body: NameTags(member: person)),
      ),
    );

    expect(find.byType(AppTag), findsNothing);
    expect(find.byType(ClanTagChip), findsNothing);
  });
}
