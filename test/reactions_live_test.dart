import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000001';
const _channelMessagesPath =
    '/api/v9/channels/${SessionHarness.channelId}/messages';
const _strangerId = '100000000000000003';
const _fire = '🔥';
const _fireEmoji = {'id': null, 'name': _fire};
const _spark = '✨';
const _sparkEmoji = {'id': null, 'name': _spark};

/// A message in the guild's first channel.
Map<String, Object?> _message({
  String id = _messageId,
  String authorId = SessionHarness.friendId,
  String timestamp = '2026-07-25T10:00:00+00:00',
  List<Object?>? reactions,
}) => {
  ...rawMessage(
    id: id,
    channelId: SessionHarness.channelId,
    guildId: SessionHarness.guildId,
    authorId: authorId,
    content: 'react to this',
    timestamp: timestamp,
  ),
  'reactions': ?reactions,
};

/// One entry of a message's `reactions` list, as the history route sends it.
Map<String, Object?> _rawReaction(
  Map<String, Object?> emoji, {
  required int count,
  bool me = false,
}) => {
  'count': count,
  'count_details': {'normal': count, 'burst': 0},
  'me': me,
  'me_burst': false,
  'emoji': emoji,
  'burst_colors': <String>[],
};

/// A reaction dispatch as Discord sends it. Which fields it needs depends on
/// the event, so a test that clears reactions passes only what it uses.
Map<String, Object?> _reaction({
  String? userId,
  String messageId = _messageId,
  Map<String, Object?>? emoji = _fireEmoji,
}) => {
  'user_id': ?userId,
  'channel_id': SessionHarness.channelId,
  'message_id': messageId,
  'guild_id': SessionHarness.guildId,
  'emoji': ?emoji,
  'type': 0,
  'burst': false,
};

Finder _chip(int count, {String emoji = _fire}) =>
    find.bySemanticsLabel('$emoji reaction, $count');

Finder _anyChip({String emoji = _fire}) =>
    find.bySemanticsLabel(RegExp('^$emoji reaction, '));

/// The route a reaction click and its undo both go to.
String _ownReactionPath({String messageId = _messageId}) =>
    '$_channelMessagesPath/$messageId'
    '/reactions/${Uri.encodeComponent(_fire)}/@me';

void _routeHistory(FakeDiscordTransport transport, List<Object?> messages) =>
    transport.on('GET', _channelMessagesPath, (_) => jsonResponse(messages));

Future<void> _openChannelWithMessage(SessionHarness session) async {
  await session.openChannel(SessionHarness.channelId);
  await session.dispatch('MESSAGE_CREATE', _message());
}

void main() {
  testSession('your own reaction marks the chip, and a click takes it back', (
    tester,
    session,
  ) async {
    session.transport.on(
      'DELETE',
      _ownReactionPath(),
      (_) => jsonResponse(null, statusCode: 204),
    );
    await _openChannelWithMessage(session);

    await session.dispatch(
      'MESSAGE_REACTION_ADD',
      _reaction(userId: SessionHarness.currentUserId),
    );

    expect(
      tester.getSemantics(_chip(1)),
      isSemantics(hasToggledState: true, isToggled: true),
    );

    await tester.tap(_chip(1));
    await session.settle();

    expect(
      session.transport.requests.where(
        (request) =>
            request.method == 'DELETE' &&
            request.uri.path == _ownReactionPath(),
      ),
      hasLength(1),
    );

    await session.dispatch(
      'MESSAGE_REACTION_REMOVE',
      _reaction(userId: SessionHarness.currentUserId),
    );

    expect(_anyChip(), findsNothing);
  });

  testSession(
    'a remove lowers the count on screen',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      expect(_chip(3), findsOneWidget);

      await session.dispatch(
        'MESSAGE_REACTION_REMOVE',
        _reaction(userId: SessionHarness.friendId),
      );

      expect(_chip(2), findsOneWidget);
      expect(_chip(3), findsNothing);
    },
    routes: (transport) => _routeHistory(transport, [
      _message(reactions: [_rawReaction(_fireEmoji, count: 3)]),
    ]),
  );

  testSession("other people's reactions appear live, and a click adds yours", (
    tester,
    session,
  ) async {
    session.transport.on(
      'PUT',
      _ownReactionPath(),
      (_) => jsonResponse(null, statusCode: 204),
    );
    await _openChannelWithMessage(session);

    // Sent together: neither may overwrite the other.
    await session.dispatch(
      'MESSAGE_REACTION_ADD',
      _reaction(userId: SessionHarness.friendId),
      settle: false,
    );
    await session.dispatch(
      'MESSAGE_REACTION_ADD',
      _reaction(userId: _strangerId),
    );

    expect(
      tester.getSemantics(_chip(2)),
      isSemantics(hasToggledState: true, isToggled: false),
    );

    await tester.tap(_chip(2));
    await session.settle();

    expect(
      session.transport.requests.where(
        (request) =>
            request.method == 'PUT' && request.uri.path == _ownReactionPath(),
      ),
      hasLength(1),
    );
  });

  // The cache keeps the newest messages of a channel. The workspace keeps all
  // it was given, so the oldest row of a longer page is held but not cached.
  const prunedId = '800000000000000001';
  testSession(
    'a reaction on a held message the cache has pruned still shows',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await tester.scrollUntilVisible(
        session.messageRow(prunedId),
        -2000,
        scrollable: find
            .descendant(
              of: find.byKey(
                const ValueKey('messages-${SessionHarness.channelId}'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await session.settle();

      await session.dispatch(
        'MESSAGE_REACTION_ADD',
        _reaction(userId: SessionHarness.friendId, messageId: prunedId),
      );

      expect(_chip(1), findsOneWidget);
    },
    routes: (transport) => _routeHistory(transport, [
      // Newest first, as Discord sends a page.
      for (
        var index = SqliteChatCache.historyPerChannel + 1;
        index >= 1;
        index--
      )
        _message(
          id: '${800000000000000000 + index}',
          timestamp: DateTime.utc(
            2026,
            7,
            25,
          ).add(Duration(minutes: index)).toIso8601String(),
        ),
    ]),
  );

  testSession(
    'a moderator clearing one emoji removes only that chip',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      await session.dispatch(
        'MESSAGE_REACTION_REMOVE_EMOJI',
        _reaction(emoji: _fireEmoji),
      );

      expect(_anyChip(), findsNothing);
      expect(_chip(1, emoji: _spark), findsOneWidget);
    },
    routes: (transport) => _routeHistory(transport, [
      _message(
        reactions: [
          _rawReaction(_fireEmoji, count: 3),
          _rawReaction(_sparkEmoji, count: 1),
        ],
      ),
    ]),
  );

  testSession(
    'a moderator clearing all reactions removes every chip',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      await session.dispatch(
        'MESSAGE_REACTION_REMOVE_ALL',
        _reaction(emoji: null),
      );

      expect(_anyChip(), findsNothing);
      expect(_anyChip(emoji: _spark), findsNothing);
    },
    routes: (transport) => _routeHistory(transport, [
      _message(
        reactions: [
          _rawReaction(_fireEmoji, count: 3),
          _rawReaction(_sparkEmoji, count: 1),
        ],
      ),
    ]),
  );

  testSession('a reaction on your own message leaves the channel unread', (
    tester,
    session,
  ) async {
    FontWeight? generalWeight() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(
              const ValueKey('channel-${SessionHarness.channelId}'),
            ),
            matching: find.text('general'),
          ),
        )
        .style
        ?.fontWeight;
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch(
      'MESSAGE_CREATE',
      _message(authorId: SessionHarness.currentUserId),
    );
    await session.openChannel(SessionHarness.otherChannelId);
    final readWeight = generalWeight();
    await session.dispatch(
      'MESSAGE_CREATE',
      _message(
        id: '900000000000000002',
        timestamp: '2026-07-25T10:01:00+00:00',
      ),
    );
    final unreadWeight = generalWeight();
    expect(unreadWeight, isNot(readWeight));

    await session.dispatch(
      'MESSAGE_REACTION_ADD',
      _reaction(userId: SessionHarness.friendId),
    );

    expect(generalWeight(), unreadWeight);
  });
}
