import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/discord/discord_thread_directory.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('lists active and archived posts with their opening messages', () async {
    final transport = _QueuedTransport([_page]);
    final joined = <Map<String, Object?>>[];
    final (directory, cache) = await _directory(
      transport,
      onSelfMember: joined.add,
    );

    final page = await directory.loadThreads(
      'forum-1',
      offset: 25,
      tagIds: const {'tag-1', 'tag-2'},
    );

    final uri = transport.requests.single;
    expect(uri.path, '/api/v10/channels/forum-1/threads/search');
    expect(uri.queryParametersAll, {
      'sort_by': ['last_message_time'],
      'sort_order': ['desc'],
      'limit': ['25'],
      'offset': ['25'],
      'tag': ['tag-1', 'tag-2'],
      'tag_setting': ['match_some'],
    });
    expect(page.threads.map((post) => (post.name, post.isArchived)), [
      ('still talking', false),
      ('long done', true),
    ]);
    expect(page.firstMessages.single.body, 'How do we ship this?');
    expect(page.hasMore, isTrue);
    expect(joined.single['id'], 'post-2');
    expect((await cache.readMessage('post-2'))?.channelId, 'post-2');
    expect(
      (await cache.readWorkspace())?.channelById('post-1').isArchived,
      true,
    );
  });

  test('asks again while Discord is still indexing the channel', () async {
    final transport = _QueuedTransport([
      '{"message":"Index not yet available.","code":110000,'
          '"documents_indexed":0,"retry_after":2}',
      _page,
    ]);
    final waits = <Duration>[];
    final (directory, _) = await _directory(transport, wait: waits.add);

    final page = await directory.loadThreads(
      'forum-1',
      offset: 0,
      tagIds: const {},
    );

    expect(waits, [const Duration(seconds: 2)]);
    expect(transport.requests, hasLength(2));
    expect(page.threads, hasLength(2));
  });
}

Future<(DiscordThreadDirectory, SqliteChatCache)> _directory(
  _QueuedTransport transport, {
  void Function(Map<String, Object?>)? onSelfMember,
  void Function(Duration)? wait,
}) async {
  final cache = await SqliteChatCache.openAt(
    inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  addTearDown(cache.close);
  await cache.writeWorkspace(_workspace);
  final client = DiscordApiClient(botToken: 'token', transport: transport);
  addTearDown(client.close);
  return (
    DiscordThreadDirectory(
      routes: client.threads,
      cache: cache,
      mapper: DiscordMapper(),
      currentMemberId: () => 'user-1',
      onSelfMember: onSelfMember,
      wait: (duration) async => wait?.call(duration),
    ),
    cache,
  );
}

const _page =
    '{"threads":['
    '{"id":"post-2","guild_id":"guild-1","parent_id":"forum-1",'
    '"name":"still talking","type":11,"last_message_id":"9",'
    '"thread_metadata":{"archived":false,'
    '"auto_archive_duration":4320,"locked":false}},'
    '{"id":"post-1","guild_id":"guild-1","parent_id":"forum-1",'
    '"name":"long done","type":11,'
    '"thread_metadata":{"archived":true,'
    '"auto_archive_duration":4320,"locked":false}}],'
    '"members":[{"id":"post-2","user_id":"user-1",'
    '"join_timestamp":"2026-07-23T09:00:00.000Z","flags":1}],'
    '"has_more":true,"total_results":40,'
    '"first_messages":[{"id":"post-2","channel_id":"post-2",'
    '"content":"How do we ship this?",'
    '"timestamp":"2026-07-23T09:00:00.000Z","edited_timestamp":null,'
    '"pinned":false,"attachments":[],"embeds":[],"reactions":[],'
    '"author":{"id":"user-2","username":"mira"}}]}';

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
    ),
  ],
  members: const [],
  messages: const [],
  currentMemberId: 'user-1',
);

/// Answers each request with the next body, 202 for a body naming no threads.
final class _QueuedTransport implements DiscordHttpTransport {
  _QueuedTransport(this._bodies);

  final List<String> _bodies;
  final List<Uri> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(uri);
    final next = _bodies.removeAt(0);
    return DiscordHttpResponse(
      statusCode: next.contains('"threads"') ? 200 : 202,
      headers: const {},
      body: next,
    );
  }

  @override
  void close() {}
}
