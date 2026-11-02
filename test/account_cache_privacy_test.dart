import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/chat_image_disk.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _privateText = 'the private words of the first account';
const _friendName = 'Private Friend Name';
const _channelName = 'private-channel-name';
const _dmMessageId = '900000000000000001';
const _guildMessageId = '900000000000000002';
const _secondAccountId = '100000000000000009';

final _unavailable = jsonResponse({'message': 'Unavailable'}, statusCode: 503);
final _firstAccountName = find.text('first-account');
final _guildIcon = find.byKey(
  const ValueKey('space-${SessionHarness.guildId}'),
);
final _dmRow = find.byKey(
  const ValueKey('channel-${SessionHarness.dmChannelId}'),
);

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

  testSession(
    'an offline launch of the same account still shows its cache',
    (tester, session) async {
      await _receivePrivateMessages(session);

      session.transport.on(
        'GET',
        '/api/v9/channels/${SessionHarness.dmChannelId}/messages',
        (_) => _unavailable,
      );
      await session.relaunchUnreachable();

      expect(_firstAccountName, findsOneWidget);
      expect(_guildIcon, findsOneWidget);
      await tester.tap(_dmRow);
      await session.settleServerErrorRepeats();
      expect(session.messageRow(_dmMessageId), findsOneWidget);
    },
    onDisk: true,
    ready: _readyOf(SessionHarness.currentUserId),
  );

  testSession(
    'a second account whose launch fails sees nothing of the first',
    (tester, session) async {
      await _receivePrivateMessages(session);

      await session.relaunchUnreachable(accountId: _secondAccountId);

      expect(_firstAccountName, findsNothing);
      expect(_guildIcon, findsNothing);
      expect(_dmRow, findsNothing);
      expect(find.textContaining(_privateText), findsNothing);
    },
    onDisk: true,
    ready: _readyOf(SessionHarness.currentUserId),
  );

  testSession(
    'a second account that connects finds no message of the first',
    (tester, session) async {
      await _receivePrivateMessages(session);

      await session.relaunch(
        accountId: _secondAccountId,
        ready: _readyOf(_secondAccountId, username: 'second-account'),
      );
      // Discord does not answer, so only the cache can fill the channel.
      session.transport.on(
        'GET',
        '/api/v9/channels/${SessionHarness.channelId}/messages',
        (_) => _unavailable,
      );
      await session.openChannel(SessionHarness.channelId);
      await session.settleServerErrorRepeats();

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('account-panel-name')))
            .data,
        'second-account',
      );
      expect(_firstAccountName, findsNothing);
      expect(session.messageRow(_guildMessageId), findsNothing);
      expect(session.cacheBytesOnDisk, isNot(contains(_privateText)));
    },
    onDisk: true,
    ready: _readyOf(SessionHarness.currentUserId),
  );

  group('the pictures of a chat', () {
    final images = ChatImageDisk.declare();

    /// A DM of the first account shows a picture, and the test waits until the
    /// picture and its address are on disk.
    Future<void> receivePicture(
      WidgetTester tester,
      SessionHarness session,
      String path,
    ) async {
      final address = images.serve(path, images.largePhoto);
      await session.dispatch('MESSAGE_CREATE', {
        ...rawMessage(
          id: _dmMessageId,
          channelId: SessionHarness.dmChannelId,
          authorId: SessionHarness.friendId,
          content: _privateText,
        ),
        'embeds': [
          {
            'type': 'rich',
            'image': {
              'url': 'https://pictures.example/original',
              'proxy_url': address,
              'width': 3000,
              'height': 2000,
            },
          },
        ],
      });
      // The cache's index reaches the disk some seconds after the download.
      await tester.pump(const Duration(seconds: 4));
      // Without this check, a cache that was never written would also pass.
      await images.waitUntil(
        tester,
        () =>
            images.bytesOnDisk.contains(ChatImageDisk.pictureMark) &&
            images.bytesOnDisk.contains(path),
        'the picture and its address on disk',
      );
    }

    testSession(
      'a second account that connects finds no picture of the first',
      (tester, session) async {
        const path = '/external/private/second-account.png';
        await receivePicture(tester, session, path);

        await session.relaunch(
          accountId: _secondAccountId,
          ready: _readyOf(_secondAccountId, username: 'second-account'),
        );

        expect(images.bytesOnDisk, isNot(contains(ChatImageDisk.pictureMark)));
        expect(images.bytesOnDisk, isNot(contains(path)));

        await images.letTimersEnd(tester);
      },
      onDisk: true,
      chatImagesOnDisk: true,
      ready: _readyOf(SessionHarness.currentUserId),
    );

    testSession(
      'signing out leaves no picture of the account and no address on disk',
      (tester, session) async {
        const path = '/external/private/photo.png';
        await receivePicture(tester, session, path);

        await session.signOut();

        expect(images.bytesOnDisk, isNot(contains(ChatImageDisk.pictureMark)));
        expect(images.bytesOnDisk, isNot(contains(path)));

        await images.letTimersEnd(tester);
      },
      onDisk: true,
      chatImagesOnDisk: true,
      ready: _readyOf(SessionHarness.currentUserId),
    );
  });

  group('the bot transport', () {
    setUpAll(sqfliteFfiInit);

    /// A launch of [accountId] with Discord unreachable, on a cache that the
    /// first account filled.
    Future<ChatWorkspace> launchOfflineAs(String accountId) async {
      final cache = await SqliteChatCache.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      await cache.writeWorkspace(
        ChatWorkspace(
          spaces: const [
            CommunitySpace(
              id: SessionHarness.guildId,
              name: 'The Forge',
              monogram: 'TF',
              colorValue: 0,
            ),
          ],
          channels: [],
          members: [],
          messages: [],
          currentMemberId: SessionHarness.currentUserId,
        ),
      );
      final repository = DiscordChatRepository(
        DiscordApiClient(
          botToken: 'unused',
          transport: FakeDiscordTransport(fallback: (_) => _unavailable),
        ),
        DiscordGatewayClient(botToken: 'unused'),
        cache,
        accountId: accountId,
      );
      addTearDown(repository.close);
      return repository.loadWorkspace();
    }

    test('an offline launch of the same account shows its cache', () async {
      final workspace = await launchOfflineAs(SessionHarness.currentUserId);

      expect(workspace.currentMemberId, SessionHarness.currentUserId);
    });

    test('an offline launch of a second account is refused', () {
      expect(
        launchOfflineAs(_secondAccountId),
        throwsA(isA<DiscordApiException>()),
      );
    });
  });
}
