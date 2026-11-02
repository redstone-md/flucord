import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_chat_repository.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';
import 'support/fake_chat_gateway.dart';

const _firstId = '900000000000000001';
const _secondId = '900000000000000002';
const _keptId = '900000000000000003';

Map<String, Object?> _message(String id) => rawMessage(
  id: id,
  channelId: SessionHarness.channelId,
  guildId: SessionHarness.guildId,
  authorId: SessionHarness.friendId,
  content: 'message $id',
);

const _bulkDelete = {
  'ids': [_firstId, _secondId],
  'channel_id': SessionHarness.channelId,
  'guild_id': SessionHarness.guildId,
};

void main() {
  setUpAll(sqfliteFfiInit);

  group('desktop transport', () {
    testSession('a bulk delete takes every named message off the screen', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      for (final id in [_firstId, _secondId, _keptId]) {
        await session.dispatch('MESSAGE_CREATE', _message(id));
      }

      await session.dispatch('MESSAGE_DELETE_BULK', _bulkDelete);

      expect(session.messageRow(_firstId), findsNothing);
      expect(session.messageRow(_secondId), findsNothing);
      expect(session.messageRow(_keptId), findsOneWidget);
    });

    testSession('a late edit cannot bring a bulk deleted message back', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch('MESSAGE_CREATE', _message(_firstId));
      await session.dispatch('MESSAGE_DELETE_BULK', _bulkDelete);

      // An edit rebuilds its message from the cache, so a copy left there would
      // put the row back.
      await session.dispatch('MESSAGE_UPDATE', _message(_firstId));

      expect(session.messageRow(_firstId), findsNothing);
    });
  });

  test(
    'bot transport: a bulk delete leaves the workspace and the cache',
    () async {
      final cache = await SqliteChatCache.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      final gateway = FakeChatGateway();
      final repository = DiscordChatRepository(
        DiscordApiClient(
          botToken: 'token',
          transport: FakeDiscordTransport(fallback: _botRoutes),
        ),
        gateway,
        cache,
      );
      addTearDown(repository.close);
      await repository.loadWorkspace();
      final deleted = repository.events.firstWhere(
        (event) => event is MessagesDeletedEvent,
      );
      for (final id in [_firstId, _secondId, _keptId]) {
        gateway.dispatch('MESSAGE_CREATE', _message(id));
      }
      await repository.events.firstWhere(
        (event) => event is MessageUpsertedEvent && event.message.id == _keptId,
      );

      gateway.dispatch('MESSAGE_DELETE_BULK', _bulkDelete);

      expect(
        await deleted,
        isA<MessagesDeletedEvent>()
            .having((event) => event.messageIds, 'ids', {_firstId, _secondId})
            .having(
              (event) => event.channelId,
              'channel',
              SessionHarness.channelId,
            ),
      );
      expect(await cache.readMessage(_firstId), isNull);
      expect(await cache.readMessage(_secondId), isNull);
      expect(await cache.readMessage(_keptId), isNotNull);
    },
  );
}

DiscordHttpResponse _botRoutes(RecordedRequest request) {
  final path = request.uri.path;
  if (path.endsWith('/users/@me')) {
    return jsonResponse({'id': 'bot-1', 'username': 'Flucord Bot'});
  }
  if (path.endsWith('/users/@me/guilds')) return jsonResponse(<Object?>[]);
  if (path.endsWith('/gateway/bot')) {
    return jsonResponse({'url': 'wss://gateway.discord.gg'});
  }
  return notFound(request);
}
