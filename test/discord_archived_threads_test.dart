import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/thread_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'pages, maps, and persists documented public archived threads',
    () async {
      final cache = await SqliteChatCache.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      await cache.writeWorkspace(_workspace);
      final transport = _RecordingTransport(
        const DiscordHttpResponse(
          statusCode: 200,
          headers: {},
          body:
              '{"threads":[{"id":"thread-1","guild_id":"guild-1",'
              '"parent_id":"channel-1","name":"old-release","type":11,'
              '"thread_metadata":{"archived":true,"locked":true,'
              '"auto_archive_duration":1440,'
              '"archive_timestamp":"2026-07-22T01:30:00.000Z"}}],'
              '"members":[],"has_more":true}',
        ),
      );
      final repository = DiscordChatRepository(
        DiscordApiClient(botToken: 'token', transport: transport),
        _FakeGateway(),
        cache,
      );
      addTearDown(repository.close);

      final page = await repository.loadArchivedThreads(
        'channel-1',
        before: DateTime.utc(2026, 7, 23, 3, 47),
      );

      expect(transport.method, 'GET');
      expect(
        transport.uri!.path,
        '/api/v10/channels/channel-1/threads/archived/public',
      );
      expect(transport.uri!.queryParameters, {
        'limit': '50',
        'before': '2026-07-23T03:47:00.000Z',
      });
      expect(page, isA<ArchivedThreadPage>());
      expect(page.threads, hasLength(1));
      expect(page.hasMore, isTrue);
      expect(page.nextBefore?.toUtc(), DateTime.utc(2026, 7, 22, 1, 30));
      final thread = page.threads.single;
      expect(thread.isThread, isTrue);
      expect(thread.isArchived, isTrue);
      expect(thread.isLocked, isTrue);
      expect(thread.autoArchiveDurationMinutes, 1440);
      expect(thread.parentId, 'channel-1');

      final restored = await cache.readWorkspace();
      final cached = restored!.channelById('thread-1');
      expect(cached.isArchived, isTrue);
      expect(cached.isLocked, isTrue);
      expect(
        cached.archiveTimestamp?.toUtc(),
        DateTime.utc(2026, 7, 22, 1, 30),
      );
    },
  );

  test('stops pagination when Discord omits an archive cursor', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    await cache.writeWorkspace(_workspace);
    final repository = DiscordChatRepository(
      DiscordApiClient(
        botToken: 'token',
        transport: _RecordingTransport(
          const DiscordHttpResponse(
            statusCode: 200,
            headers: {},
            body:
                '{"threads":[{"id":"thread-2","guild_id":"guild-1",'
                '"parent_id":"channel-1","name":"uncursered","type":11,'
                '"thread_metadata":{"archived":true}}],'
                '"members":[],"has_more":true}',
          ),
        ),
      ),
      _FakeGateway(),
      cache,
    );
    addTearDown(repository.close);

    final page = await repository.loadArchivedThreads('channel-1');

    expect(page.hasMore, isFalse);
    expect(page.nextBefore, isNull);
  });
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'channel-1',
      spaceId: 'guild-1',
      name: 'general',
      topic: 'General',
      kind: ChannelKind.text,
    ),
  ],
  members: const [
    Member(
      id: 'bot-1',
      displayName: 'Flucord',
      initials: 'FL',
      role: 'Bot',
      presence: Presence.online,
      colorValue: 0xff456b5a,
    ),
  ],
  messages: const [],
  currentMemberId: 'bot-1',
);

final class _RecordingTransport implements DiscordHttpTransport {
  _RecordingTransport(this.response);

  final DiscordHttpResponse response;
  String? method;
  Uri? uri;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    this.method = method;
    this.uri = uri;
    return response;
  }

  @override
  void close() {}
}

final class _FakeGateway implements DiscordChatGateway {
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();

  @override
  Stream<DiscordGatewayEvent> get events => _events.stream;

  @override
  Future<void> connect(String gatewayUrl) async {}

  @override
  void updateVoiceState({
    required String guildId,
    required String? channelId,
    bool selfMute = false,
    bool selfDeaf = false,
  }) {}

  @override
  void pingVoiceServer() {}

  @override
  Future<void> close() => _events.close();
}
