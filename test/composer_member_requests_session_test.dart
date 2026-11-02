import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _anna = '700000000000000001';
const _aaron = '700000000000000002';
const _abby = '700000000000000003';

/// What Discord sends in answer to opcode 8.
Map<String, Object?> _chunk(Map<String, String> namesById) => {
  'guild_id': SessionHarness.guildId,
  'members': [
    for (final MapEntry(key: id, value: name) in namesById.entries)
      {
        'user': {'id': id, 'username': name.toLowerCase(), 'global_name': name},
        'roles': <String>[],
      },
  ],
};

extension on SessionHarness {
  /// The query of each member request that went out, in order.
  Iterable<Object?> get memberRequests => socket.frames
      .where((frame) => frame['op'] == 8)
      .map((frame) => (frame['d']! as Map)['query']);
}

Finder _suggestion(String memberId) =>
    find.byKey(ValueKey('composer-suggestion-member-$memberId'));

Future<void> _type(
  WidgetTester tester,
  SessionHarness session,
  String text,
) async {
  await tester.enterText(find.byKey(const ValueKey('message-composer')), text);
  await session.settle();
}

void main() {
  testSession('an open query sends one member request while updates arrive', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('GUILD_MEMBERS_CHUNK', _chunk({_anna: 'Anna'}));
    await _type(tester, session, '@a');
    expect(_suggestion(_anna), findsOneWidget);

    await session.dispatch('GUILD_MEMBERS_CHUNK', _chunk({_aaron: 'Aaron'}));
    await session.dispatch(
      'MESSAGE_CREATE',
      rawMessage(
        id: '900000000000000001',
        channelId: SessionHarness.channelId,
        guildId: SessionHarness.guildId,
        authorId: SessionHarness.friendId,
        content: 'hello',
      ),
    );
    await session.dispatch('GUILD_MEMBERS_CHUNK', _chunk({_abby: 'Abby'}));

    expect(session.memberRequests, ['a']);
  });

  testSession('changing the query sends one more member request', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('GUILD_MEMBERS_CHUNK', _chunk({_anna: 'Anna'}));
    await _type(tester, session, '@a');

    // Nobody loaded matches this one, which is when asking matters most.
    await _type(tester, session, '@ab');

    expect(session.memberRequests, ['a', 'ab']);
  });

  testSession('a member chunk adds its members to the open list', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('GUILD_MEMBERS_CHUNK', _chunk({_anna: 'Anna'}));
    await _type(tester, session, '@a');
    expect(_suggestion(_aaron), findsNothing);

    await session.dispatch('GUILD_MEMBERS_CHUNK', _chunk({_aaron: 'Aaron'}));

    expect(_suggestion(_anna), findsOneWidget);
    expect(_suggestion(_aaron), findsOneWidget);
  });

  testSession('a member chunk opens the list for a query nobody matched yet', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await _type(tester, session, '@abb');
    expect(find.byKey(const ValueKey('composer-autocomplete')), findsNothing);
    expect(session.memberRequests, ['abb']);

    await session.dispatch('GUILD_MEMBERS_CHUNK', _chunk({_abby: 'Abby'}));

    expect(_suggestion(_abby), findsOneWidget);
    expect(session.memberRequests, ['abb']);
  });

  testSession('a direct message sends no member request', (
    tester,
    session,
  ) async {
    await session.openChannel(
      SessionHarness.dmChannelId,
      space: 'direct-messages',
    );
    await _type(tester, session, '@f');

    expect(_suggestion(SessionHarness.friendId), findsOneWidget);
    expect(session.memberRequests, isEmpty);
  });

  testSession('a list closed with Esc stays closed when members arrive', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('GUILD_MEMBERS_CHUNK', _chunk({_anna: 'Anna'}));
    await _type(tester, session, '@a');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await session.settle();
    await session.dispatch('GUILD_MEMBERS_CHUNK', _chunk({_aaron: 'Aaron'}));

    expect(find.byKey(const ValueKey('composer-autocomplete')), findsNothing);
    expect(session.memberRequests, ['a']);
  });
}
