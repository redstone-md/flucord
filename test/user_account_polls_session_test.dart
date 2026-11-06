import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _pollId = '900000000000000011';

const _generalPath = '/api/v9/channels/${SessionHarness.channelId}/messages';
const _votePath =
    '/api/v9/channels/${SessionHarness.channelId}/polls/$_pollId/answers/@me';

/// Polls, driven as a person on their own account drives them: through the
/// screen, down to the request Discord gets and the dispatches it sends back.
void main() {
  testSession('a poll made in the composer is sent and shows', (
    tester,
    session,
  ) async {
    session.transport.on(
      'POST',
      _generalPath,
      (_) => jsonResponse(_poll(authorId: SessionHarness.currentUserId)),
    );
    await session.openChannel(SessionHarness.channelId);

    await tester.tap(find.byKey(const ValueKey('composer-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-poll')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('poll-question')),
      'Which build ships?',
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll-answer-0')),
      'Stable',
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll-answer-1')),
      'Canary',
    );
    await tester.tap(find.byKey(const ValueKey('create-poll-confirm')));
    await session.settle();

    final sent = session.transport.requests.lastWhere(
      (request) => request.method == 'POST' && request.uri.path == _generalPath,
    );
    final poll = (sent.json! as Map)['poll'] as Map;
    expect(poll['question'], {'text': 'Which build ships?'});
    expect(session.messageRow(_pollId), findsOneWidget);
    expect(find.text('Which build ships?'), findsOneWidget);
  });

  testSession('a tap votes, another tap changes the vote, Remove takes it '
      'back', (tester, session) async {
    session.transport.on(
      'PUT',
      _votePath,
      (_) => const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
    );
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('MESSAGE_CREATE', _poll());

    await tester.tap(find.byKey(const ValueKey('poll-answer-1')));
    await session.settle();
    expect(_votes(session), [
      [1],
    ]);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('poll-answer-2')));
    await session.settle();
    // Discord echoes the change, which was already counted.
    await session.dispatch('MESSAGE_POLL_VOTE_REMOVE', _vote(1));
    await session.dispatch('MESSAGE_POLL_VOTE_ADD', _vote(2));
    expect(_votes(session).last, [2]);
    expect(find.textContaining('1 vote'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('poll-remove-vote')));
    await session.settle();
    expect(_votes(session).last, isEmpty);
    expect(find.textContaining('0 votes'), findsOneWidget);
  });

  testSession('a vote from somebody else counts live', (tester, session) async {
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('MESSAGE_CREATE', _poll());

    await session.dispatch(
      'MESSAGE_POLL_VOTE_ADD',
      _vote(2, userId: SessionHarness.friendId),
    );

    expect(find.textContaining('1 vote'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testSession('the voters of an answer are listed', (tester, session) async {
    session.transport.on(
      'GET',
      '/api/v9/channels/${SessionHarness.channelId}/polls/$_pollId/answers/1',
      (_) => jsonResponse({
        'users': [
          {
            'id': SessionHarness.friendId,
            'username': 'friend',
            'global_name': 'Friend',
          },
        ],
      }),
    );
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('MESSAGE_CREATE', _poll(stableVotes: 1));

    await tester.tap(find.byKey(const ValueKey('poll-voters')));
    await session.settle();

    expect(find.byKey(const ValueKey('poll-voters-answer-1')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Friend')),
      findsOneWidget,
    );
  });

  testSession('an ended poll shows its results and offers no vote', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch(
      'MESSAGE_CREATE',
      _poll(stableVotes: 1, finalized: true),
    );

    await tester.tap(find.byKey(const ValueKey('poll-answer-2')));
    await session.settle();

    expect(
      session.transport.requests.where((request) => request.method == 'PUT'),
      isEmpty,
    );
    expect(find.textContaining('Poll ended'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });
}

/// The answer ids of every vote the account sent, oldest first.
List<Object?> _votes(SessionHarness session) => [
  for (final request in session.transport.requests)
    if (request.method == 'PUT' && request.uri.path == _votePath)
      (request.json! as Map)['answer_ids'],
];

Map<String, Object?> _vote(
  int answerId, {
  String userId = SessionHarness.currentUserId,
}) => {
  'user_id': userId,
  'channel_id': SessionHarness.channelId,
  'message_id': _pollId,
  'guild_id': SessionHarness.guildId,
  'answer_id': answerId,
};

/// A one-answer poll in #general from a friend, unless [authorId] says who.
Map<String, Object?> _poll({
  String authorId = SessionHarness.friendId,
  int stableVotes = 0,
  bool finalized = false,
}) => {
  ...rawMessage(
    id: _pollId,
    channelId: SessionHarness.channelId,
    authorId: authorId,
    content: '',
    guildId: SessionHarness.guildId,
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
    'expiry': finalized
        ? '2026-01-01T00:00:00+00:00'
        : '2099-01-01T00:00:00+00:00',
    'allow_multiselect': false,
    'layout_type': 1,
    'results': {
      'is_finalized': finalized,
      'answer_counts': [
        if (stableVotes > 0) {'id': 1, 'count': stableVotes, 'me_voted': false},
      ],
    },
  },
};
