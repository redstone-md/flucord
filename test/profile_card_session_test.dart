import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// FLUCORD-87: a member, an author or a friend opens the one profile card,
// beside the name that opened it.

const _messageId = '900000000000000041';

final _card = find.byKey(const ValueKey('profile-card'));
final _addFriend = find.byKey(const ValueKey('profile-card-add-friend'));
final _messageField = find.byKey(const ValueKey('profile-card-message'));

Future<void> _openAuthorCard(
  WidgetTester tester,
  SessionHarness session, {
  String authorId = SessionHarness.friendId,
}) async {
  await session.openChannel(SessionHarness.channelId);
  await session.dispatch(
    'MESSAGE_CREATE',
    rawMessage(
        id: _messageId,
        channelId: SessionHarness.channelId,
        guildId: SessionHarness.guildId,
        authorId: authorId,
        content: 'hello',
      )
      ..['author'] = {
        'id': authorId,
        'username': 'handle-$authorId',
        'global_name': 'Name',
      },
  );
  await tester.tap(_authorName(session));
  await session.settle();
}

Finder _authorName(SessionHarness session) => find.descendant(
  of: session.messageRow(_messageId),
  matching: find.byKey(const ValueKey('message-author-name')),
);

Iterable<RecordedRequest> _requests(
  SessionHarness session,
  String method,
  String path,
) => session.transport.requests.where(
  (request) => request.method == method && request.uri.path == path,
);

void main() {
  testSession('an author opens the card beside their name', (
    tester,
    session,
  ) async {
    await _openAuthorCard(tester, session);

    expect(_card, findsOneWidget);
    final nameRect = tester.getRect(_authorName(session));
    final cardRect = tester.getRect(_card);
    expect(cardRect.left, greaterThanOrEqualTo(nameRect.right));
    // Level with the name, or moved up as far as it takes to stay on screen.
    expect(cardRect.top, lessThanOrEqualTo(nameRect.top));
    expect(cardRect.bottom, lessThanOrEqualTo(720 - 8));
    expect(
      find.descendant(
        of: _card,
        matching: find.text('handle-${SessionHarness.friendId}'),
      ),
      findsOneWidget,
    );
  }, size: const Size(1280, 720));

  testSession(
    'the message field opens the DM and sends what was typed',
    (tester, session) async {
      await _openAuthorCard(tester, session);

      await tester.enterText(_messageField, 'gg');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await session.settle();

      expect(_card, findsNothing);
      final sent = _requests(
        session,
        'POST',
        '/api/v9/channels/${SessionHarness.dmChannelId}/messages',
      );
      expect((sent.single.json! as Map)['content'], 'gg');
    },
    routes: _routeOpenDm,
  );

  testSession(
    'a message Discord refuses waits in the DM box',
    (tester, session) async {
      session.transport.on(
        'POST',
        '/api/v9/channels/${SessionHarness.dmChannelId}/messages',
        (_) => jsonResponse({
          'code': 50007,
          'message': 'Cannot send messages to this user',
        }, statusCode: 403),
      );
      await _openAuthorCard(tester, session);

      await tester.enterText(_messageField, 'gg');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await session.settle();

      expect(_card, findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('message-composer')),
            )
            .controller!
            .text,
        'gg',
      );
    },
    routes: _routeOpenDm,
  );

  testSession('add friend asks Discord for a friendship', (
    tester,
    session,
  ) async {
    await _openAuthorCard(tester, session);

    await tester.tap(_addFriend);
    await session.settle();

    expect(
      _requests(
        session,
        'PUT',
        '/api/v9/users/@me/relationships/${SessionHarness.friendId}',
      ),
      hasLength(1),
    );
  });

  testSession('a friend is not offered add friend', (tester, session) async {
    await _openAuthorCard(tester, session);

    expect(_card, findsOneWidget);
    expect(_addFriend, findsNothing);
  }, ready: _readyAsFriends());

  testSession('your own card has no message field and no add friend', (
    tester,
    session,
  ) async {
    await _openAuthorCard(
      tester,
      session,
      authorId: SessionHarness.currentUserId,
    );

    expect(_card, findsOneWidget);
    expect(_messageField, findsNothing);
    expect(_addFriend, findsNothing);
  });
}

/// The default READY, with the friend as an actual friend.
Map<String, Object?> _readyAsFriends() =>
    SessionHarness.defaultReady()
      ..['relationships'] = [
        {
          'id': SessionHarness.friendId,
          'type': 1,
          'user': {'id': SessionHarness.friendId, 'username': 'friend'},
        },
      ];

/// Discord answers the DM open with the DM the account already has.
void _routeOpenDm(FakeDiscordTransport transport) => transport.on(
  'POST',
  '/api/v9/users/@me/channels',
  (_) => jsonResponse({
    'id': SessionHarness.dmChannelId,
    'type': 1,
    'recipients': [
      {'id': SessionHarness.friendId, 'username': 'friend'},
    ],
  }),
);
