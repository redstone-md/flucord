import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// Messages from blocked people (FLUCORD-121): each run of them folds into one
// row that can be opened and closed, a reply hides what it quotes from them,
// and a block or unblock changes an open timeline at once.

/// Discord's relationship type for a block.
const _blockedType = 2;

const _first = '900000000000000101';
const _second = '900000000000000102';
const _own = '900000000000000103';
const _third = '900000000000000104';

Map<String, Object?> _blockedRelationship() => {
  'id': SessionHarness.friendId,
  'type': _blockedType,
  'user': {'id': SessionHarness.friendId, 'username': 'friend'},
};

Map<String, Object?> _readyWithBlock() =>
    SessionHarness.defaultReady()..['relationships'] = [_blockedRelationship()];

Map<String, Object?> _message(String id, String authorId, String content) =>
    rawMessage(
      id: id,
      channelId: SessionHarness.channelId,
      guildId: SessionHarness.guildId,
      authorId: authorId,
      content: content,
    );

/// Two messages from the friend, one of the account's own, then one more
/// from the friend.
Future<void> _sendConversation(SessionHarness session) async {
  await session.openChannel(SessionHarness.channelId);
  for (final (id, author, text) in [
    (_first, SessionHarness.friendId, 'first'),
    (_second, SessionHarness.friendId, 'second'),
    (_own, SessionHarness.currentUserId, 'mine'),
    (_third, SessionHarness.friendId, 'third'),
  ]) {
    await session.dispatch(
      'MESSAGE_CREATE',
      _message(id, author, text),
      settle: false,
    );
  }
  await session.settle();
}

/// The timeline row of the message [id], for finders built outside a test.
Finder _row(String id) => find.byKey(ValueKey('message-$id'));

Finder _fold(String firstMessageId) =>
    find.byKey(ValueKey('blocked-messages-$firstMessageId'));

Finder _toggle(String firstMessageId) => find.descendant(
  of: _fold(firstMessageId),
  matching: find.byKey(const ValueKey('blocked-messages-toggle')),
);

void main() {
  testSession('each run of blocked messages folds into one row', (
    tester,
    session,
  ) async {
    await _sendConversation(session);

    expect(
      find.descendant(
        of: _fold(_first),
        matching: find.text('2 blocked messages'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _fold(_third),
        matching: find.text('1 blocked message'),
      ),
      findsOneWidget,
    );
    expect(_fold(_second), findsNothing);
    for (final id in [_first, _second, _third]) {
      expect(session.messageRow(id), findsNothing);
    }
    expect(session.messageRow(_own), findsOneWidget);
  }, ready: _readyWithBlock());

  testSession('Show opens a run and Hide folds it again', (
    tester,
    session,
  ) async {
    await _sendConversation(session);

    await tester.tap(_toggle(_first));
    await session.settle();

    expect(session.messageRow(_first), findsOneWidget);
    expect(session.messageRow(_second), findsOneWidget);
    // Only the run that was opened.
    expect(session.messageRow(_third), findsNothing);
    expect(
      find.descendant(of: _toggle(_first), matching: find.text('Hide')),
      findsOneWidget,
    );

    await tester.tap(_toggle(_first));
    await session.settle();

    expect(session.messageRow(_first), findsNothing);
    expect(session.messageRow(_second), findsNothing);
    expect(
      find.descendant(of: _toggle(_first), matching: find.text('Show')),
      findsOneWidget,
    );
  }, ready: _readyWithBlock());

  testSession(
    'an unblock shows the messages, and a block folds them, without a reload',
    (tester, session) async {
      await _sendConversation(session);

      await session.dispatch('RELATIONSHIP_REMOVE', {
        'id': SessionHarness.friendId,
        'type': _blockedType,
      });

      expect(_fold(_first), findsNothing);
      expect(_fold(_third), findsNothing);
      for (final id in [_first, _second, _own, _third]) {
        expect(session.messageRow(id), findsOneWidget);
      }

      await session.dispatch('RELATIONSHIP_ADD', _blockedRelationship());

      expect(_fold(_first), findsOneWidget);
      expect(session.messageRow(_first), findsNothing);
    },
    ready: _readyWithBlock(),
  );

  testSession(
    'a run opened before an unblock folds again on a new block',
    (tester, session) async {
      await _sendConversation(session);
      await tester.tap(_toggle(_first));
      await session.settle();

      await session.dispatch('RELATIONSHIP_REMOVE', {
        'id': SessionHarness.friendId,
        'type': _blockedType,
      });
      await session.dispatch('RELATIONSHIP_ADD', _blockedRelationship());

      expect(session.messageRow(_first), findsNothing);
      expect(
        find.descendant(of: _toggle(_first), matching: find.text('Show')),
        findsOneWidget,
      );
    },
    ready: _readyWithBlock(),
  );

  group('a reply to a blocked message', () {
    const replyId = '900000000000000200';
    final preview = find.descendant(
      of: _row(replyId),
      matching: find.byKey(const ValueKey('message-reply-preview')),
    );

    Future<void> sendReply(SessionHarness session) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch('MESSAGE_CREATE', {
        ..._message(replyId, SessionHarness.currentUserId, 'my answer'),
        'referenced_message': _message(
          _first,
          SessionHarness.friendId,
          'the question',
        ),
      });
    }

    Finder quoted(String text) =>
        find.descendant(of: preview, matching: find.text(text));

    testSession('hides the quote until it is asked for', (
      tester,
      session,
    ) async {
      await sendReply(session);

      expect(quoted('Blocked message'), findsOneWidget);
      expect(quoted('the question'), findsNothing);

      await tester.tap(preview);
      await session.settle();

      expect(quoted('the question'), findsOneWidget);
    }, ready: _readyWithBlock());

    testSession('a jump to the quoted message opens its run', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch(
        'MESSAGE_CREATE',
        _message(_first, SessionHarness.friendId, 'the question'),
      );
      await sendReply(session);

      // The first tap shows the quote, the second goes to it.
      await tester.tap(preview);
      await session.settle();
      await tester.tap(preview);
      await session.settle();

      expect(session.messageRow(_first), findsOneWidget);
    }, ready: _readyWithBlock());

    testSession('shows the quote once the person is unblocked', (
      tester,
      session,
    ) async {
      await sendReply(session);

      await session.dispatch('RELATIONSHIP_REMOVE', {
        'id': SessionHarness.friendId,
      });

      expect(quoted('the question'), findsOneWidget);
    }, ready: _readyWithBlock());
  });
}
