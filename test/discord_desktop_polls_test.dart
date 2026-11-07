import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/poll_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_discord_wire.dart';

const _account = '100000000000000001';
const _voter = '100000000000000002';
const _channel = '300000000000000003';
const _message = '400000000000000004';

const _votePath = '/api/v9/channels/$_channel/polls/$_message/answers/@me';

/// The poll routes a user account uses, as Userdoccers lists them: each test
/// reads back the request Discord gets.
void main() {
  setUpAll(sqfliteFfiInit);

  group('vote', () {
    test('puts the chosen answers and counts the vote at once', () async {
      final transport = FakeDiscordTransport()
        ..on('PUT', _votePath, (_) => _noContent());
      final (repository, _) = await _repository(transport);

      final voted = await (repository as PollVoteRepository).votePoll(
        channelId: _channel,
        messageId: _message,
        answerIds: {2},
      );

      final request = transport.requests.last;
      expect(request.method, 'PUT');
      expect(request.uri.path, _votePath);
      expect(request.json, {
        'answer_ids': [2],
      });
      final answers = voted.poll!.answers;
      expect(answers.map((answer) => answer.count), [4, 3]);
      expect(answers.map((answer) => answer.votedByCurrentUser), [false, true]);
    });

    test('no answers takes the vote back', () async {
      final transport = FakeDiscordTransport()
        ..on('PUT', _votePath, (_) => _noContent());
      final (repository, _) = await _repository(transport, ownVote: 1);

      final cleared = await (repository as PollVoteRepository).votePoll(
        channelId: _channel,
        messageId: _message,
        answerIds: const {},
      );

      expect(transport.requests.last.json, {'answer_ids': <int>[]});
      expect(cleared.poll!.answers.map((answer) => answer.count), [3, 2]);
      expect(cleared.poll!.answers.any((a) => a.votedByCurrentUser), isFalse);
    });

    test('a refusal reaches the caller as Discord said it', () async {
      final transport = FakeDiscordTransport()
        ..on(
          'PUT',
          _votePath,
          (_) => jsonResponse({
            'message': 'Poll expired',
            'code': 520001,
          }, statusCode: 400),
        );
      final (repository, cache) = await _repository(transport);

      await expectLater(
        (repository as PollVoteRepository).votePoll(
          channelId: _channel,
          messageId: _message,
          answerIds: {1},
        ),
        throwsA(isA<DiscordApiException>()),
      );
      final held = await cache.readMessage(_message);
      expect(held!.poll!.answers.map((answer) => answer.count), [4, 2]);
    });
  });

  test('lists the voters of one answer, a page at a time', () async {
    const votersPath = '/api/v9/channels/$_channel/polls/$_message/answers/2';
    final transport = FakeDiscordTransport()
      ..on(
        'GET',
        votersPath,
        (_) => jsonResponse({
          'users': [
            {'id': _voter, 'username': 'ivy', 'global_name': 'Ivy'},
          ],
        }),
      );
    final (repository, _) = await _repository(transport);

    final page = await (repository as PollRepository).loadPollVoters(
      channelId: _channel,
      messageId: _message,
      answerId: 2,
      afterUserId: _account,
      limit: 1,
    );

    final request = transport.requests.last;
    expect(request.uri.path, votersPath);
    expect(request.uri.queryParameters, {'after': _account, 'limit': '1'});
    expect(page.users.single.displayName, 'Ivy');
    expect(page.hasMore, isTrue);
  });

  test('a poll is sent with the message, under a nonce', () async {
    final transport = FakeDiscordTransport()
      ..on(
        'POST',
        '/api/v9/channels/$_channel/messages',
        (_) => jsonResponse(_pollMessage()),
      );
    final (repository, _) = await _repository(transport);

    final created = await (repository as PollRepository).createPoll(
      channelId: _channel,
      authorId: _account,
      poll: PendingPoll(
        question: 'Which build ships?',
        answers: const ['Stable', 'Canary'],
        durationHours: 24,
        allowMultiselect: true,
      ),
    );

    final body = transport.requests.last.json! as Map<String, Object?>;
    expect(body['content'], '');
    expect(body['nonce'], isA<String>());
    expect(body['poll'], {
      'question': {'text': 'Which build ships?'},
      'answers': [
        {
          'poll_media': {'text': 'Stable'},
        },
        {
          'poll_media': {'text': 'Canary'},
        },
      ],
      'duration': 24,
      'allow_multiselect': true,
      'layout_type': 1,
    });
    expect(created.poll?.question, 'Which build ships?');
  });

  test('ending a poll posts to its expire route', () async {
    const expirePath = '/api/v9/channels/$_channel/polls/$_message/expire';
    final transport = FakeDiscordTransport()
      ..on(
        'POST',
        expirePath,
        (_) => jsonResponse(_pollMessage(finalized: true)),
      );
    final (repository, _) = await _repository(transport);

    final ended = await (repository as PollRepository).endPoll(
      channelId: _channel,
      messageId: _message,
    );

    expect(transport.requests.last.uri.path, expirePath);
    expect(ended.poll?.isFinalized, isTrue);
  });
}

DiscordHttpResponse _noContent() =>
    const DiscordHttpResponse(statusCode: 204, headers: {}, body: '');

/// A poll in [_channel] with four votes for "Stable" and two for "Canary".
/// [ownVote] names the answer the account already chose, if any.
Map<String, Object?> _pollMessage({int? ownVote, bool finalized = false}) => {
  ...rawMessage(
    id: _message,
    channelId: _channel,
    authorId: _voter,
    content: '',
  ),
  'poll': {
    'question': {'text': 'Which build ships?'},
    'answers': [
      {
        'answer_id': 1,
        'poll_media': {'text': 'Stable'},
      },
      {
        'answer_id': 2,
        'poll_media': {'text': 'Canary'},
      },
    ],
    'expiry': '2099-01-01T00:00:00+00:00',
    'allow_multiselect': false,
    'layout_type': 1,
    'results': {
      'is_finalized': finalized,
      'answer_counts': [
        {'id': 1, 'count': 4, 'me_voted': ownVote == 1},
        {'id': 2, 'count': 2, 'me_voted': ownVote == 2},
      ],
    },
  },
};

/// A repository over [transport], with the poll of [_pollMessage] cached.
Future<(DiscordDesktopChatRepository, ChatCache)> _repository(
  FakeDiscordTransport transport, {
  int? ownVote,
}) async {
  final cache = await SqliteChatCache.openAt(
    inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  await cache.writeMessage(
    DiscordMapper().message(
      _pollMessage(ownVote: ownVote),
      currentMemberId: _account,
    ),
  );
  final repository = DiscordDesktopChatRepository(
    DiscordDesktopApiClient(
      authorization: 'account-session',
      headers: const {},
      transport: transport,
    ),
    // Never dialled: these are REST routes, and the repository only needs a
    // gateway to exist.
    DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {'os': 'Windows'},
      socketConnector: MemoryDesktopWebSocketConnector(),
    ),
    cache,
  );
  addTearDown(repository.close);
  return (repository, cache);
}
