import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _privateText = 'the private words of the first account';
const _friendName = 'Private Friend Name';
const _channelName = 'private-channel-name';
const _dmMessageId = '900000000000000001';
const _guildMessageId = '900000000000000002';

/// READY for an account in [SessionHarness.guildId], with one DM to a friend.
Map<String, Object?> _readyOf(
  String accountId, {
  String username = 'first-account',
}) => {
  ...SessionHarness.defaultReady(),
  'user': {'id': accountId, 'username': username},
  'users': [
    {
      'id': SessionHarness.friendId,
      'username': 'friend',
      'global_name': _friendName,
    },
  ],
  'guilds': [
    rawGuild(
      id: SessionHarness.guildId,
      name: 'The Forge',
      channels: [rawChannel(id: SessionHarness.channelId, name: _channelName)],
    ),
  ],
};

/// A DM and a guild message of the first account reach the cache.
Future<void> _receivePrivateMessages(SessionHarness session) async {
  await session.dispatch(
    'MESSAGE_CREATE',
    rawMessage(
      id: _dmMessageId,
      channelId: SessionHarness.dmChannelId,
      authorId: SessionHarness.friendId,
      content: _privateText,
    ),
  );
  await session.dispatch(
    'MESSAGE_CREATE',
    rawMessage(
      id: _guildMessageId,
      channelId: SessionHarness.channelId,
      guildId: SessionHarness.guildId,
      authorId: SessionHarness.friendId,
      content: _privateText,
    ),
  );
}

void main() {
  testSession(
    'signing out leaves no message, member or channel of the account on disk',
    (tester, session) async {
      await _receivePrivateMessages(session);
      // Without this check, a cache that was never written would also pass.
      expect(session.cacheBytesOnDisk, contains(_privateText));
      expect(session.cacheBytesOnDisk, contains(_friendName));
      expect(session.cacheBytesOnDisk, contains(_channelName));

      await session.signOut();

      expect(session.cacheBytesOnDisk, isNot(contains(_privateText)));
      expect(session.cacheBytesOnDisk, isNot(contains(_friendName)));
      expect(session.cacheBytesOnDisk, isNot(contains(_channelName)));
    },
    onDisk: true,
    ready: _readyOf(SessionHarness.currentUserId),
  );
}
