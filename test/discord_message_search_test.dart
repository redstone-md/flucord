import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/discord/discord_message_search_service.dart';
import 'package:flucord/src/data/discord/discord_message_search_wire.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/message_search.dart';

part 'discord_message_search_poll_cases.dart';

/// R05 fixes the whole request in the query string, so the serialisation is
/// the contract: a wrong parameter name is a silently broader search.
void main() {
  group('query serialisation', () {
    test('names the classic routes for both scopes', () {
      expect(
        DiscordMessageSearchWire.pathFor(
          const GuildMessageSearchScope('111111111111111111'),
        ),
        '/guilds/111111111111111111/messages/search',
      );
      expect(
        DiscordMessageSearchWire.pathFor(
          const ChannelMessageSearchScope('222222222222222222'),
        ),
        '/channels/222222222222222222/messages/search',
      );
    });

    test('carries every filter, repeating list-valued keys', () {
      final parameters = DiscordMessageSearchWire.parametersFor(
        MessageSearchQuery(
          filters: MessageSearchFilters(
            content: '  release notes  ',
            authorIds: const ['123456789012345678', '123456789012345678'],
            mentionIds: const ['234567890123456789'],
            has: const [
              MessageSearchHas(MessageSearchHasKind.image),
              MessageSearchHas(MessageSearchHasKind.video, negated: true),
            ],
            channelIds: const ['333333333333333333'],
            pinned: true,
            minId: '987654321098765432',
            maxId: '111111111111111111',
          ),
          sort: MessageSearchSort.mostRelevant,
          offset: 50,
        ),
      );

      expect(parameters['content'], 'release notes');
      // The client accumulates each filter into a set, so a value typed twice
      // is sent once.
      expect(parameters['author_id'], const ['123456789012345678']);
      expect(parameters['mentions'], const ['234567890123456789']);
      expect(parameters['has'], const ['image', '-video']);
      expect(parameters['channel_id'], const ['333333333333333333']);
      expect(parameters['pinned'], 'true');
      expect(parameters['min_id'], '987654321098765432');
      expect(parameters['max_id'], '111111111111111111');
      expect(parameters['sort_by'], 'relevance');
      expect(parameters['sort_order'], 'desc');
      expect(parameters['offset'], '50');
      expect(parameters.containsKey('attempts'), isFalse);
      // Never claimed on the account's behalf: the desktop client only sends
      // it once the user agreed to age-restricted content for that guild.
      expect(parameters.containsKey('include_nsfw'), isFalse);
    });

    test('omits every filter the user did not set', () {
      final parameters = DiscordMessageSearchWire.parametersFor(
        MessageSearchQuery(filters: MessageSearchFilters(content: 'ship')),
      );

      expect(parameters.keys, {'content', 'sort_by', 'sort_order', 'offset'});
      expect(parameters['sort_by'], 'timestamp');
      expect(parameters['sort_order'], 'desc');
    });

    test('drops an empty content bucket and sends the retry counter', () {
      final parameters = DiscordMessageSearchWire.parametersFor(
        MessageSearchQuery(
          filters: MessageSearchFilters(
            content: '   ',
            pinned: false,
            authorIds: const [],
          ),
          sort: MessageSearchSort.oldest,
        ),
        attempts: 3,
      );

      expect(parameters.containsKey('content'), isFalse);
      expect(parameters.containsKey('author_id'), isFalse);
      expect(parameters['pinned'], 'false');
      expect(parameters['sort_order'], 'asc');
      expect(parameters['attempts'], '3');
    });

    test('a scope is identified by what it searches', () {
      final guildId = '111111111111111111';
      final channelId = '222222222222222222';

      expect(GuildMessageSearchScope(guildId).key, 'guild:$guildId');
      expect(ChannelMessageSearchScope(channelId).key, 'channel:$channelId');
      expect(
        GuildMessageSearchScope(guildId),
        const GuildMessageSearchScope('111111111111111111'),
      );
      expect(
        GuildMessageSearchScope(guildId).hashCode,
        const GuildMessageSearchScope('111111111111111111').hashCode,
      );
      expect(
        ChannelMessageSearchScope(channelId),
        const ChannelMessageSearchScope('222222222222222222'),
      );
      expect(
        ChannelMessageSearchScope(channelId).hashCode,
        const ChannelMessageSearchScope('222222222222222222').hashCode,
      );
      // A guild and a channel that share an id are still different corpora.
      expect(
        GuildMessageSearchScope(channelId) ==
            ChannelMessageSearchScope(channelId),
        isFalse,
      );
      expect(
        const MessageSearchHas(
          MessageSearchHasKind.image,
          negated: true,
        ).toString(),
        contains('-image'),
      );
    });

    test('sort modes round-trip through the wire pair', () {
      for (final sort in MessageSearchSort.values) {
        expect(
          MessageSearchSort.fromWire(
            sortBy: sort.sortBy,
            sortOrder: sort.sortOrder,
          ),
          sort,
        );
      }
      expect(MessageSearchSort.fromWire(), MessageSearchSort.newest);
      expect(
        MessageSearchSort.fromWire(sortBy: 'timestamp'),
        MessageSearchSort.newest,
      );
    });
  });

  group('envelope mapping', () {
    test('keeps a hit group whole and marks the flagged message', () {
      final results = DiscordMapper().searchResults(
        _envelope(),
        fallbackSpaceId: '111111111111111111',
      );

      expect(results.totalResults, 3);
      expect(results.analyticsId, 'analytics-1');
      expect(results.groups, hasLength(1));
      final group = results.groups.single;
      // A group is the hit plus its context; nothing is thrown away.
      expect(group.messages.map((message) => message.id), const [
        '111111111111111111',
        '222222222222222222',
        '333333333333333333',
      ]);
      expect(group.hitIndex, 1);
      expect(group.hit.id, '222222222222222222');
      expect(group.hasContext, isTrue);
      expect(
        results.authors.map((author) => author.id),
        contains('123456789012345678'),
      );
      expect(
        results.channels.map((channel) => channel.name),
        containsAll(const ['release', 'release-thread']),
      );
      expect(results.doingDeepHistoricalIndex, isTrue);
      expect(results.documentsIndexed, 4200);
    });

    test('falls back to the first message when nothing carries the flag', () {
      final envelope = _envelope();
      for (final raw in (envelope['messages']! as List).first as List) {
        (raw as Map).remove('hit');
      }
      for (final key in const ['channels', 'threads']) {
        for (final raw in envelope[key]! as List) {
          (raw as Map).remove('guild_id');
        }
      }

      final results = DiscordMapper().searchResults(envelope);

      expect(results.groups.single.hitIndex, 0);
      // The channel-scoped route names no guild, and with no fallback there is
      // nothing to file these channels under, so none is invented.
      expect(results.channels, isEmpty);
    });

    test('skips groups and entries a message cannot be built from', () {
      final results = DiscordMapper().searchResults({
        'total_results': 1,
        'messages': [
          'not-a-group',
          [
            {'id': '111111111111111111'},
            {'content': 'no id'},
          ],
          [
            {
              'id': '234567890123456789',
              'channel_id': '333333333333333333',
              'timestamp': '2024-05-01T10:00:00.000Z',
              'author': {'id': '123456789012345678', 'username': 'ada'},
              'content': 'kept',
            },
          ],
        ],
      });

      expect(results.groups, hasLength(1));
      expect(results.groups.single.hit.body, 'kept');
    });

    test('floors a negative total and caps what pagination can reach', () {
      final negative = DiscordMapper().searchResults({
        'total_results': -1,
        'documents_indexed': -5,
        'messages': const [],
      });
      expect(negative.totalResults, 0);
      expect(negative.documentsIndexed, 0);
      expect(negative.pageCount, 0);
      expect(negative.isEmpty, isTrue);

      final huge = DiscordMapper().searchResults({
        'total_results': 999999,
        'messages': const [],
      });
      expect(huge.reachableTotal, MessageSearchQuery.reachableResults);
      expect(huge.isTotalLimited, isTrue);
      expect(huge.pageCount, MessageSearchQuery.maxPageIndex + 1);

      final small = DiscordMapper().searchResults({
        'total_results': 26,
        'messages': const [],
      });
      expect(small.pageCount, 2);
      expect(small.isTotalLimited, isFalse);
    });

    test('rejects a hit group it cannot point at', () {
      expect(
        () => MessageSearchHitGroup(messages: const [], hitIndex: 0),
        throwsArgumentError,
      );
      expect(
        () => MessageSearchHitGroup(
          messages: [_message('111111111111111111')],
          hitIndex: 4,
        ),
        throwsRangeError,
      );
    });
  });

  _pollCases();

  group('rest transport', () {
    test('surfaces the status and Retry-After of a 202', () async {
      final transport = _RecordingTransport();
      final client = DiscordDesktopApiClient(
        authorization: 'user-authorization',
        headers: const {},
        transport: transport,
        baseUri: Uri.parse('https://discord.test/api/v9'),
      );
      addTearDown(client.close);

      final response = await client.searchMessages(
        '/guilds/111111111111111111/messages/search',
        const {
          'content': 'notes',
          'has': ['image', 'video'],
        },
      );

      expect(response.statusCode, 202);
      expect(response.retryAfter, const Duration(seconds: 7));
      // A repeated key is how a list-valued filter travels.
      expect(transport.uri!.query, 'content=notes&has=image&has=video');
    });

    test('reads Retry-After the way parseInt does', () {
      Duration? retryAfter(String value) => DiscordApiResponse(
        statusCode: 202,
        headers: {'retry-after': value},
        payload: null,
      ).retryAfter;

      expect(retryAfter('3'), const Duration(seconds: 3));
      expect(retryAfter('3.9'), const Duration(seconds: 3));
      expect(retryAfter('0'), isNull);
      expect(retryAfter('soon'), isNull);
      expect(
        const DiscordApiResponse(
          statusCode: 202,
          headers: {},
          payload: null,
        ).retryAfter,
        isNull,
      );
    });
  });
}

DiscordMessageSearchService _service(
  _SearchTransport transport,
  List<Duration> delays,
) => DiscordMessageSearchService(
  requester: transport.send,
  delay: (duration) async => delays.add(duration),
);

MessageSearchRequest _request({int offset = 0}) => MessageSearchRequest(
  scope: const GuildMessageSearchScope('111111111111111111'),
  query: MessageSearchQuery(
    filters: MessageSearchFilters(content: 'release'),
    offset: offset,
  ),
);

DiscordApiResponse _accepted({String? retryAfter}) => DiscordApiResponse(
  statusCode: 202,
  headers: {'retry-after': ?retryAfter},
  payload: const <String, Object?>{},
);

DiscordApiResponse _ok() => DiscordApiResponse(
  statusCode: 200,
  headers: const {},
  payload: _envelope(),
);

Map<String, Object?> _envelope() => {
  'analytics_id': 'analytics-1',
  'total_results': 3,
  'doing_deep_historical_index': true,
  'documents_indexed': 4200,
  'messages': [
    [
      _rawMessage(id: '111111111111111111', content: 'before the hit'),
      _rawMessage(
        id: '222222222222222222',
        content: 'release notes are up',
        hit: true,
        mentions: true,
      ),
      _rawMessage(id: '333333333333333333', content: 'after the hit'),
    ],
  ],
  'channels': [
    {
      'id': '333333333333333333',
      'guild_id': '111111111111111111',
      'name': 'release',
      'type': 0,
    },
  ],
  'threads': [
    {
      'id': '987654321098765432',
      'guild_id': '111111111111111111',
      'name': 'release-thread',
      'type': 11,
    },
  ],
  // Thread members, not guild members: never fed to the workspace's roster.
  'members': [
    {'id': '987654321098765432', 'user_id': '123456789012345678', 'flags': 0},
  ],
};

Map<String, Object?> _rawMessage({
  required String id,
  required String content,
  bool hit = false,
  bool mentions = false,
}) => {
  'id': id,
  'channel_id': '333333333333333333',
  'timestamp': '2024-05-01T10:00:00.000Z',
  'content': content,
  'author': {'id': '123456789012345678', 'username': 'ada'},
  'mentions': [
    if (mentions) {'id': '234567890123456789', 'username': 'grace'},
  ],
  if (hit) 'hit': true,
};

dynamic _message(String id) => DiscordMapper().message({
  'id': id,
  'channel_id': '333333333333333333',
  'timestamp': '2024-05-01T10:00:00.000Z',
  'content': 'body',
  'author': {'id': '123456789012345678', 'username': 'ada'},
});

final class _SearchTransport {
  _SearchTransport(this.responses);

  final List<DiscordApiResponse> responses;
  final List<Map<String, Object?>> queries = [];
  int _index = 0;

  Future<DiscordApiResponse> send(String path, Map<String, Object?> query) {
    queries.add(query);
    return Future.value(responses[_index++]);
  }
}

final class _RecordingTransport implements DiscordHttpTransport {
  Uri? uri;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    this.uri = uri;
    return DiscordHttpResponse(
      statusCode: 202,
      headers: const {'retry-after': '7'},
      body: jsonEncode(const <String, Object?>{}),
    );
  }

  @override
  void close() {}
}
