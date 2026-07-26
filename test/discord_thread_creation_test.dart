import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('creates, maps, and persists a documented message thread', () async {
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
            '{"id":"message-1","guild_id":"guild-1",'
            '"parent_id":"channel-1","name":"release-checklist",'
            '"type":11}',
      ),
    );
    final repository = DiscordChatRepository(
      DiscordApiClient(botToken: 'token', transport: transport),
      _FakeGateway(),
      cache,
    );
    addTearDown(repository.close);

    final thread = await repository.createThreadFromMessage(
      channelId: 'channel-1',
      messageId: 'message-1',
      name: 'release-checklist',
      autoArchiveDurationMinutes: 4320,
    );

    expect(thread.id, 'message-1');
    expect(thread.parentId, 'channel-1');
    expect(thread.isThread, isTrue);
    expect(transport.method, 'POST');
    expect(
      transport.uri!.path,
      '/api/v10/channels/channel-1/messages/message-1/threads',
    );
    expect(jsonDecode(utf8.decode(transport.body!)), {
      'name': 'release-checklist',
      'auto_archive_duration': 4320,
    });
    final restored = await cache.readWorkspace();
    expect(restored?.channelById('message-1').isThread, isTrue);
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
  List<int>? body;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    this.method = method;
    this.uri = uri;
    this.body = body;
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
