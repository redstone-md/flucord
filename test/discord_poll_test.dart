import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/discord/discord_message_nonce_factory.dart';
import 'package:flucord/src/data/discord/discord_poll_vote_handler.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('maps poll answers, results, and partial updates', () {
    final mapper = DiscordMapper();
    final message = mapper.message(_messagePayload(count: 4));

    expect(message.poll?.question, 'Which build ships?');
    expect(message.poll?.answers, hasLength(2));
    expect(message.poll?.answers.first.text, 'Stable');
    expect(message.poll?.answers.first.emojiName, '✅');
    expect(message.poll?.answers.first.count, 4);
    expect(message.poll?.answers.first.votedByCurrentUser, isTrue);
    expect(message.poll?.allowMultiselect, isFalse);

    final updated = mapper.message({
      'id': 'poll-1',
      'poll': {
        ...(_messagePayload(count: 8)['poll']! as Map),
        'results': {
          'is_finalized': true,
          'answer_counts': [
            {'id': 1, 'count': 8, 'me_voted': true},
            {'id': 2, 'count': 2, 'me_voted': false},
          ],
        },
      },
    }, fallback: message);

    expect(updated.body, message.body);
    expect(updated.poll?.answers.first.count, 8);
    expect(updated.poll?.isFinalized, isTrue);
  });

  test('sends the documented poll payload and expire route', () async {
    final transport = _RecordingTransport([
      DiscordHttpResponse(
        statusCode: 200,
        headers: const {},
        body: jsonEncode(_messagePayload(count: 0)),
      ),
      DiscordHttpResponse(
        statusCode: 200,
        headers: const {},
        body: jsonEncode(_messagePayload(count: 0)),
      ),
    ]);
    final client = DiscordApiClient(botToken: 'token', transport: transport);
    addTearDown(client.close);

    await client.createMessage(
      channelId: 'channel-1',
      content: '',
      poll: PendingPoll(
        question: 'Which build ships?',
        answers: const ['Stable', 'Canary'],
        durationHours: 72,
        allowMultiselect: true,
      ),
    );
    await client.endPoll(channelId: 'channel-1', messageId: 'poll-1');

    expect(transport.requests.first.method, 'POST');
    expect(
      transport.requests.first.uri.path,
      '/api/v10/channels/channel-1/messages',
    );
    expect(jsonDecode(utf8.decode(transport.requests.first.body!)), {
      'content': '',
      'poll': {
        'question': {'text': 'Which build ships?'},
        'answers': [
          {
            'poll_media': {'text': 'Stable'},
          },
          {
            'poll_media': {'text': 'Canary'},
          },
        ],
        'duration': 72,
        'allow_multiselect': true,
        'layout_type': 1,
      },
    });
    expect(
      transport.requests.last.uri.path,
      '/api/v10/channels/channel-1/polls/poll-1/expire',
    );
  });

  test('repository enforces an idempotency nonce for poll creation', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final fixedClock = DateTime.utc(2026, 7, 24, 3, 47);
    final expectedNonce =
        '${fixedClock.microsecondsSinceEpoch.toRadixString(36)}00';
    final transport = _RecordingTransport([
      DiscordHttpResponse(
        statusCode: 200,
        headers: const {},
        body: jsonEncode(_messagePayload(count: 0)),
      ),
    ]);
    final repository = DiscordChatRepository(
      DiscordApiClient(botToken: 'token', transport: transport),
      _FakeGateway(),
      cache,
      messageNonceFactory: DiscordMessageNonceFactory(clock: () => fixedClock),
    );
    addTearDown(repository.close);

    await repository.createPoll(
      channelId: 'channel-1',
      authorId: 'bot-1',
      poll: PendingPoll(
        question: 'Which build ships?',
        answers: const ['Stable', 'Canary'],
        durationHours: 72,
        allowMultiselect: true,
      ),
    );

    final body =
        jsonDecode(utf8.decode(transport.requests.single.body!)) as Map;
    expect(body['nonce'], expectedNonce);
    expect(body['enforce_nonce'], isTrue);
  });

  test('applies live poll vote add and remove events to cache', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final mapper = DiscordMapper();
    final message = mapper.message(_messagePayload(count: 4));
    await cache.writeMessage(message);
    final handler = DiscordPollVoteHandler(cache, () => 'bot-1');

    final added = await handler.apply(
      const DiscordGatewayDispatch(
        name: 'MESSAGE_POLL_VOTE_ADD',
        data: {'message_id': 'poll-1', 'answer_id': 2, 'user_id': 'bot-1'},
      ),
    );
    expect(added?.message.poll?.answers.last.count, 3);
    expect(added?.message.poll?.answers.last.votedByCurrentUser, isTrue);

    final removed = await handler.apply(
      const DiscordGatewayDispatch(
        name: 'MESSAGE_POLL_VOTE_REMOVE',
        data: {'message_id': 'poll-1', 'answer_id': 2, 'user_id': 'bot-1'},
      ),
    );
    expect(removed?.message.poll?.answers.last.count, 2);
    expect(removed?.message.poll?.answers.last.votedByCurrentUser, isFalse);
  });
}

Map<String, Object?> _messagePayload({required int count}) => {
  'id': 'poll-1',
  'channel_id': 'channel-1',
  'content': '',
  'timestamp': '2026-07-23T10:00:00.000Z',
  'edited_timestamp': null,
  'pinned': false,
  'attachments': const [],
  'embeds': const [],
  'reactions': const [],
  'author': const {'id': 'bot-1', 'username': 'Flucord'},
  'poll': {
    'question': {'text': 'Which build ships?'},
    'answers': [
      {
        'answer_id': 1,
        'poll_media': {
          'text': 'Stable',
          'emoji': {'id': null, 'name': '✅', 'animated': false},
        },
      },
      {
        'answer_id': 2,
        'poll_media': {'text': 'Canary'},
      },
    ],
    'expiry': '2026-07-26T10:00:00.000Z',
    'allow_multiselect': false,
    'layout_type': 1,
    'results': {
      'is_finalized': false,
      'answer_counts': [
        {'id': 1, 'count': count, 'me_voted': true},
        {'id': 2, 'count': 2, 'me_voted': false},
      ],
    },
  },
};

final class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    required this.body,
  });

  final String method;
  final Uri uri;
  final List<int>? body;
}

final class _RecordingTransport implements DiscordHttpTransport {
  _RecordingTransport(this.responses);

  final List<DiscordHttpResponse> responses;
  final List<_RecordedRequest> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(_RecordedRequest(method: method, uri: uri, body: body));
    return responses[requests.length - 1];
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
