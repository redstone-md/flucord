import 'package:flucord/src/app_log.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// Friend requests on the wire (FLUCORD-100): the route each one takes, and
// what the person sees when Discord answers no.

const _requestsPath = '/api/v9/users/@me/relationships';

final _usernameField = find.byKey(const ValueKey('friends-add-username'));
final _sendButton = find.byKey(const ValueKey('friends-add'));

Future<void> _openFriendsTab(
  WidgetTester tester,
  SessionHarness session,
  String tab,
) async {
  await tester.tap(find.byKey(const ValueKey('space-direct-messages')));
  await session.settle();
  await tester.tap(find.byKey(const ValueKey('toggle-friends')));
  await session.settle();
  await tester.tap(find.byKey(ValueKey('friends-tab-$tab')));
  await session.settle();
}

Future<void> _sendByUsername(
  WidgetTester tester,
  SessionHarness session,
  String username,
) async {
  await tester.enterText(_usernameField, username);
  await session.settle();
  await tester.tap(_sendButton);
  await session.settle();
}

/// The relationship writes the client sent, as "METHOD path".
List<String> _writes(SessionHarness session) => [
  for (final request in session.transport.requests)
    if (request.uri.path.startsWith(_requestsPath))
      '${request.method} ${request.uri.path}',
];

DiscordHttpResponse _noContent(RecordedRequest _) =>
    const DiscordHttpResponse(statusCode: 204, headers: {}, body: '');

void main() {
  testSession(
    'adding by username posts the name to the username route',
    (tester, session) async {
      await _openFriendsTab(tester, session, 'add');

      await _sendByUsername(tester, session, 'someone_123');

      expect(_writes(session), ['POST $_requestsPath']);
      final request = session.transport.requests.lastWhere(
        (request) => request.uri.path == _requestsPath,
      );
      expect(request.json, {'username': 'someone_123', 'discriminator': null});
      // Taken, so the field is ready for the next name.
      expect(
        tester.widget<TextField>(_usernameField).controller?.text,
        isEmpty,
      );
    },
    routes: (transport) => transport.on('POST', _requestsPath, _noContent),
  );

  testSession(
    'accepting a request and adding a suggestion go by id',
    (tester, session) async {
      await _openFriendsTab(tester, session, 'pending');
      await tester.tap(
        find.byKey(const ValueKey('friend-accept-${SessionHarness.friendId}')),
      );
      await session.settle();

      await tester.tap(find.byKey(const ValueKey('friends-tab-add')));
      await session.settle();
      await tester.tap(
        find.byKey(const ValueKey('suggestion-add-$_suggestedId')),
      );
      await session.settle();

      expect(_writes(session), [
        'PUT $_requestsPath/${SessionHarness.friendId}',
        'PUT $_requestsPath/$_suggestedId',
      ]);
    },
    ready: _readyWithIncomingRequest(),
    routes: (transport) => transport
      ..on('PUT', '$_requestsPath/${SessionHarness.friendId}', _noContent)
      ..on('PUT', '$_requestsPath/$_suggestedId', _noContent)
      ..on(
        'GET',
        '/api/v9/friend-suggestions',
        (_) => jsonResponse([_suggestion]),
      ),
  );

  testSession('each refusal reads as its own reason', (tester, session) async {
    await _openFriendsTab(tester, session, 'add');
    final cases = <(DiscordHttpResponse, String)>[
      (
        _refusal(80004),
        'Nobody has that username. Check the spelling and try again.',
      ),
      (
        _refusal(10013),
        'Nobody has that username. Check the spelling and try again.',
      ),
      (_refusal(80007), 'You are already friends.'),
      (_refusal(80000), 'This person is not accepting friend requests.'),
      (_refusal(80002), 'Bots cannot be added as friends.'),
      (_refusal(80003), 'You cannot add yourself as a friend.'),
      (_refusal(30002), 'You have reached the limit of 1,000 friends.'),
      (
        _refusal(40002),
        'Verify your account with Discord to send friend requests.',
      ),
      (_refusal(340007), 'Discord has limited your friend requests for now.'),
      (
        jsonResponse({
          'message': 'You are being rate limited.',
          'retry_after': 60,
          'global': false,
        }, statusCode: 429),
        'You are sending requests too fast. Wait a moment and try again.',
      ),
      // A code this build has no reason for still says it was refused.
      (_refusal(99999), 'Discord refused the request.'),
    ];
    for (final (answer, message) in cases) {
      session.transport.on('POST', _requestsPath, (_) => answer);

      await _sendByUsername(tester, session, 'someone_123');

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('friends-refused')),
          matching: find.text(message),
        ),
        findsOneWidget,
      );
    }
  });

  testSession(
    'a captcha is solved in place and the request goes again with its key',
    (tester, session) async {
      var asked = 0;
      session.transport.on(
        'POST',
        _requestsPath,
        (request) => asked++ == 0 ? _captchaChallenge() : _noContent(request),
      );
      await _openFriendsTab(tester, session, 'add');

      await _sendByUsername(tester, session, 'someone_123');
      expect(SessionHarness.captchaView, findsOneWidget);

      await tester.tap(SessionHarness.captchaView);
      await session.settle();

      final sent = [
        for (final request in session.transport.requests)
          if (request.uri.path == _requestsPath) request,
      ];
      expect(sent, hasLength(2));
      expect(sent.first.headers.containsKey('X-Captcha-Key'), isFalse);
      expect(
        sent.last.headers['X-Captcha-Key'],
        SessionHarness.solvedCaptchaKey,
      );
      expect(sent.last.headers['X-Captcha-Rqtoken'], 'rq-token');
      expect(sent.last.json, {
        'username': 'someone_123',
        'discriminator': null,
      });
      expect(SessionHarness.captchaView, findsNothing);
      expect(
        tester.widget<TextField>(_usernameField).controller?.text,
        isEmpty,
      );
    },
  );

  testSession('a refusal is logged with its status and code, not the name', (
    tester,
    session,
  ) async {
    final log = <String>[];
    AppLog.redirect = (level, scope, message, error) => log.add(message);
    addTearDown(() => AppLog.redirect = null);
    session.transport.on('POST', _requestsPath, (_) => _refusal(80004));
    await _openFriendsTab(tester, session, 'add');

    await _sendByUsername(tester, session, 'someone_123');

    expect(
      log,
      contains('friend request by username refused, status 400, code 80004'),
    );
    expect(log.where((line) => line.contains('someone_123')), isEmpty);
  });

  testSession('a request that fails is shown, not dropped', (
    tester,
    session,
  ) async {
    session.transport.on(
      'POST',
      _requestsPath,
      (_) => jsonResponse({'message': 'Oops'}, statusCode: 500),
    );
    await _openFriendsTab(tester, session, 'add');

    await _sendByUsername(tester, session, 'someone_123');

    expect(find.byKey(const ValueKey('friends-error')), findsOneWidget);
  });

  testSession(
    'suggestions that fail to load are shown, not dropped',
    (tester, session) async {
      await _openFriendsTab(tester, session, 'all');

      expect(find.byKey(const ValueKey('friends-error')), findsOneWidget);
    },
    routes: (transport) => transport.on(
      'GET',
      '/api/v9/friend-suggestions',
      (_) => jsonResponse({'message': 'Forbidden'}, statusCode: 403),
    ),
  );
}

const _suggestedId = '100000000000000088';

const _suggestion = {
  'suggested_user': {
    'id': _suggestedId,
    'username': 'maybe',
    'global_name': 'Maybe',
    'avatar': 'abc123',
  },
  'reasons': <Object?>[],
};

Map<String, Object?> _readyWithIncomingRequest() =>
    SessionHarness.defaultReady()
      ..['relationships'] = [
        {
          'id': SessionHarness.friendId,
          'type': 3,
          'user': {
            'id': SessionHarness.friendId,
            'username': 'friend',
            'global_name': 'Friend',
          },
        },
      ];

DiscordHttpResponse _refusal(int code) =>
    jsonResponse({'code': code, 'message': 'Refused'}, statusCode: 400);

/// Discord's answer when it wants a captcha first.
DiscordHttpResponse _captchaChallenge() => jsonResponse({
  'captcha_key': ['captcha-required'],
  'captcha_sitekey': 'site-key',
  'captcha_service': 'hcaptcha',
  'captcha_rqdata': 'rq-data',
  'captcha_rqtoken': 'rq-token',
}, statusCode: 400);
