import 'package:flucord/src/domain/discord_snowflake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _channelId = SessionHarness.channelId;
const _otherChannelId = SessionHarness.otherChannelId;
const _guildId = SessionHarness.guildId;
const _accountId = SessionHarness.currentUserId;
const _messageId = '900000000000000001';
const _laterMessageId = '900000000000000002';

Map<String, Object?> _message(
  String id, {
  String channelId = _channelId,
  String content = 'hello',
}) => rawMessage(
  id: id,
  channelId: channelId,
  guildId: _guildId,
  authorId: SessionHarness.friendId,
  content: content,
);

/// A moment of screen time that is much shorter than the wait for a flush.
Future<void> _someFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testSession('a message shows before its cache write finishes', (
    tester,
    session,
  ) async {
    await session.openChannel(_channelId);

    await session.dispatch(
      'MESSAGE_CREATE',
      _message(_messageId),
      settle: false,
    );
    await _someFrames(tester);

    expect(session.messageRow(_messageId), findsOneWidget);
    expect(await session.messageOnDisk(_messageId), isFalse);

    await session.settle();
    expect(await session.messageOnDisk(_messageId), isTrue);
  }, onDisk: true);

  testSession('a burst of messages takes one commit', (tester, session) async {
    final ids = [
      for (var index = 0; index < 20; index++) '90000000000000${1000 + index}',
    ];
    await session.openChannel(_channelId);
    final before = session.cacheCommits;

    for (final id in ids) {
      await session.dispatch('MESSAGE_CREATE', _message(id), settle: false);
    }
    await session.settle();

    expect(session.cacheCommits - before, 1);
    for (final id in ids) {
      expect(await session.messageOnDisk(id), isTrue, reason: id);
    }
  }, onDisk: true);

  testSession('the database runs in WAL with normal sync', (
    tester,
    session,
  ) async {
    expect(await session.cachePragma('journal_mode'), 'wal');
    // SQLite's number for NORMAL.
    expect(await session.cachePragma('synchronous'), 1);
  }, onDisk: true);

  group('a delete before the flush', () {
    testSession('leaves no row behind', (tester, session) async {
      await session.openChannel(_channelId);

      await session.dispatch(
        'MESSAGE_CREATE',
        _message(_messageId),
        settle: false,
      );
      await session.dispatch('MESSAGE_DELETE', const {
        'id': _messageId,
        'channel_id': _channelId,
        'guild_id': _guildId,
      }, settle: false);
      await session.settle();

      expect(session.messageRow(_messageId), findsNothing);
      expect(await session.messageOnDisk(_messageId), isFalse);
    }, onDisk: true);

    testSession('of a message already written still removes it', (
      tester,
      session,
    ) async {
      await session.openChannel(_channelId);
      await session.dispatch('MESSAGE_CREATE', _message(_messageId));
      expect(await session.messageOnDisk(_messageId), isTrue);

      await session.dispatch('MESSAGE_DELETE', const {
        'id': _messageId,
        'channel_id': _channelId,
        'guild_id': _guildId,
      });

      expect(await session.messageOnDisk(_messageId), isFalse);
    }, onDisk: true);
  });

  testSession('changes right behind a new message all reach the cache', (
    tester,
    session,
  ) async {
    await session.openChannel(_channelId);

    await session.dispatch(
      'MESSAGE_CREATE',
      _message(_messageId, content: 'first'),
      settle: false,
    );
    await session.dispatch('MESSAGE_REACTION_ADD', const {
      'channel_id': _channelId,
      'guild_id': _guildId,
      'message_id': _messageId,
      'user_id': SessionHarness.friendId,
      'emoji': {'id': null, 'name': '🔥'},
    }, settle: false);
    await session.dispatch(
      'MESSAGE_UPDATE',
      _message(_messageId, content: 'second'),
      settle: false,
    );
    await session.settle();

    final cached = await session.cachedMessage(_messageId);
    expect(cached?.body, 'second');
    expect(cached?.reactions.single.count, 1);
  });

  testSession('a crash loses only what has not been flushed', (
    tester,
    session,
  ) async {
    await session.openChannel(_channelId);
    await session.dispatch('MESSAGE_CREATE', _message(_messageId));

    await session.dispatch(
      'MESSAGE_CREATE',
      _message(_laterMessageId),
      settle: false,
    );
    await _someFrames(tester);

    expect(await session.messageOnDisk(_messageId), isTrue);
    expect(await session.messageOnDisk(_laterMessageId), isFalse);
  }, onDisk: true);

  group('a message still waiting for its write', () {
    final recent = DiscordSnowflake.fromTimestampMillis(
      DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
    final cursor = DiscordSnowflake.fromTimestampMillis(
      DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
    );
    Map<String, Object?> mention(String channelId) => {
      ..._message(recent, channelId: channelId),
      'mentions': [
        {'id': _accountId, 'username': 'me'},
      ],
    };
    Finder badgeOf(String channelId) =>
        find.byKey(ValueKey('channel-mention-$channelId'));
    Map<String, Object?> ready() =>
        SessionHarness.defaultReady()
          ..['read_state'] = {
            'version': 1,
            'partial': false,
            'entries': [
              {'id': _channelId, 'last_message_id': cursor},
              {'id': _otherChannelId, 'last_message_id': cursor},
            ],
          };

    testSession(
      'draws no badge on the channel on screen',
      (tester, session) async {
        await session.openChannel(_channelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          mention(_channelId),
          settle: false,
        );
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(badgeOf(_channelId), findsNothing);
        }
        expect(session.messageRow(recent), findsOneWidget);
        expect(await session.messageOnDisk(recent), isFalse);

        await session.settle();
        expect(badgeOf(_channelId), findsNothing);
      },
      onDisk: true,
      ready: ready(),
    );

    testSession(
      'raises the badge of another channel at once',
      (tester, session) async {
        await session.openChannel(_channelId);

        await session.dispatch(
          'MESSAGE_CREATE',
          mention(_otherChannelId),
          settle: false,
        );
        await _someFrames(tester);

        expect(badgeOf(_otherChannelId), findsOneWidget);
        expect(await session.messageOnDisk(recent), isFalse);
      },
      onDisk: true,
      ready: ready(),
    );
  });

  testSession('closing the session writes what is still waiting', (
    tester,
    session,
  ) async {
    await session.openChannel(_channelId);
    await session.dispatch(
      'MESSAGE_CREATE',
      _message(_messageId),
      settle: false,
    );
    await _someFrames(tester);

    await session.relaunch(ready: SessionHarness.defaultReady());

    expect(await session.cachedMessage(_messageId), isNotNull);
  }, onDisk: true);
}
