import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('maps documented forum and media channel metadata', () {
    final mapper = DiscordMapper();

    final forum = mapper.channel({
      'id': 'forum-1',
      'type': 15,
      'name': 'field-reports',
      'topic': 'Post reports here',
      'default_auto_archive_duration': 4320,
      'default_sort_order': 1,
      'default_forum_layout': 2,
      'available_tags': [
        {
          'id': 'tag-1',
          'name': 'Client',
          'moderated': false,
          'emoji_id': null,
          'emoji_name': '🧩',
        },
      ],
    }, 'guild-1');
    final media = mapper.channel({
      'id': 'media-1',
      'type': 16,
      'name': 'captures',
    }, 'guild-1');

    expect(forum?.kind, ChannelKind.forum);
    expect(forum?.topic, 'Post reports here');
    expect(forum?.availableTags.single.name, 'Client');
    expect(forum?.availableTags.single.emojiName, '🧩');
    expect(forum?.defaultAutoArchiveDurationMinutes, 4320);
    expect(forum?.defaultSortOrder, ForumSortOrder.creationDate);
    expect(forum?.defaultForumLayout, ForumLayout.galleryView);
    expect(media?.kind, ChannelKind.media);
  });

  test('creates and persists a documented forum post', () async {
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
            '{"id":"post-1","guild_id":"guild-1","parent_id":"forum-1",'
            '"name":"native-cache","type":11,"applied_tags":["tag-1"],'
            '"thread_metadata":{"archived":false,'
            '"auto_archive_duration":4320,"locked":false},'
            '"message":{"id":"starter-1","channel_id":"post-1",'
            '"content":"SQLite v13 is live.",'
            '"timestamp":"2026-07-23T09:00:00.000Z","edited_timestamp":null,'
            '"pinned":false,"attachments":[],"embeds":[],"reactions":[],'
            '"author":{"id":"bot-1","username":"Flucord"}}}',
      ),
    );
    final repository = DiscordChatRepository(
      DiscordApiClient(botToken: 'token', transport: transport),
      _FakeGateway(),
      cache,
    );
    addTearDown(repository.close);

    final created = await repository.createForumPost(
      channelId: 'forum-1',
      name: 'native-cache',
      content: 'SQLite v13 is live.',
      autoArchiveDurationMinutes: 4320,
      appliedTagIds: const ['tag-1'],
    );

    expect(transport.method, 'POST');
    expect(transport.uri!.path, '/api/v10/channels/forum-1/threads');
    expect(jsonDecode(utf8.decode(transport.body!)), {
      'name': 'native-cache',
      'auto_archive_duration': 4320,
      'message': {'content': 'SQLite v13 is live.'},
      'applied_tags': ['tag-1'],
    });
    expect(created.thread.parentId, 'forum-1');
    expect(created.thread.appliedTagIds, ['tag-1']);
    expect(created.initialMessage.body, 'SQLite v13 is live.');
    final restored = await cache.readWorkspace();
    expect(restored?.channelById('post-1').appliedTagIds, ['tag-1']);
    expect((await cache.readMessage('starter-1'))?.channelId, 'post-1');
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
      id: 'forum-1',
      spaceId: 'guild-1',
      name: 'field-reports',
      topic: '',
      kind: ChannelKind.forum,
      availableTags: [ForumTag(id: 'tag-1', name: 'Client', moderated: false)],
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
  Future<void> close() => _events.close();
}
