import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _annId = '100000000000000011';
const _boId = '100000000000000012';
const _blockedId = '100000000000000013';
const _newDmId = '300000000000000099';

final _search = find.byKey(const ValueKey('direct-message-search'));

Finder _person(String id) => find.byKey(ValueKey('direct-message-person-$id'));

/// READY with Ann as a friend, Bo as a member of the guild only, and somebody
/// the account blocked.
Map<String, Object?> _ready() {
  final ready = SessionHarness.defaultReady();
  ready['relationships'] = [
    {
      'id': _annId,
      'type': 1,
      'user': {'id': _annId, 'username': 'ann_w', 'global_name': 'Ann'},
    },
    {
      'id': _blockedId,
      'type': 2,
      'user': {'id': _blockedId, 'username': 'blocked', 'global_name': 'Nope'},
    },
  ];
  final guild = (ready['guilds']! as List).first as Map<String, Object?>;
  guild['members'] = [
    {
      'user': {'id': _boId, 'username': 'bo', 'global_name': 'Bo'},
      'roles': <String>[],
    },
    {
      'user': {'id': _blockedId, 'username': 'blocked', 'global_name': 'Nope'},
      'roles': <String>[],
    },
  ];
  return ready;
}

/// Discord answers with the DM it opened with whoever the body names.
void _routeOpenDm(FakeDiscordTransport transport) => transport.on(
  'POST',
  '/api/v9/users/@me/channels',
  (request) => jsonResponse({
    'id': _newDmId,
    'type': 1,
    'recipients': [
      {'id': ((request.json! as Map)['recipients'] as List).single},
    ],
  }),
);

Future<void> _openDialog(WidgetTester tester, SessionHarness session) async {
  await tester.tap(find.byKey(const ValueKey('new-direct-message')));
  await session.settle();
}

Object? _recipientsAsked(SessionHarness session) =>
    (session.transport.requests
            .singleWhere(
              (request) =>
                  request.method == 'POST' &&
                  request.uri.path == '/api/v9/users/@me/channels',
            )
            .json!
        as Map)['recipients'];

void main() {
  group('the new message dialog', () {
    testSession(
      'finds a friend by name and opens the conversation',
      (tester, session) async {
        await _openDialog(tester, session);

        await tester.enterText(_search, 'an');
        await session.settle();
        expect(_person(_annId), findsOneWidget);
        expect(_person(_boId), findsNothing);

        await tester.tap(_person(_annId));
        await session.settle();

        expect(_recipientsAsked(session), [_annId]);
        expect(_search, findsNothing);
        expect(find.byKey(const ValueKey('channel-$_newDmId')), findsOneWidget);
      },
      ready: _ready(),
      routes: _routeOpenDm,
    );

    testSession('finds a friend by username', (tester, session) async {
      await _openDialog(tester, session);

      await tester.enterText(_search, 'ANN_W');
      await session.settle();

      expect(_person(_annId), findsOneWidget);
    }, ready: _ready());

    testSession(
      'finds a member of a server',
      (tester, session) async {
        await _openDialog(tester, session);

        await tester.enterText(_search, 'bo');
        await session.settle();
        await tester.tap(_person(_boId));
        await session.settle();

        expect(_recipientsAsked(session), [_boId]);
      },
      ready: _ready(),
      routes: _routeOpenDm,
    );

    testSession(
      'opens the first match on Enter',
      (tester, session) async {
        await _openDialog(tester, session);

        await tester.enterText(_search, 'ann');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await session.settle();

        expect(_recipientsAsked(session), [_annId]);
      },
      ready: _ready(),
      routes: _routeOpenDm,
    );

    testSession(
      'lists friends first, and never the account or anybody blocked',
      (tester, session) async {
        await _openDialog(tester, session);

        expect(_person(SessionHarness.currentUserId), findsNothing);
        expect(_person(_blockedId), findsNothing);
        expect(
          tester.getTopLeft(_person(_annId)).dy,
          lessThan(tester.getTopLeft(_person(_boId)).dy),
        );
      },
      ready: _ready(),
    );

    testSession('asks for no user id', (tester, session) async {
      await _openDialog(tester, session);

      expect(find.textContaining('user ID'), findsNothing);
      await tester.enterText(_search, _annId);
      await session.settle();
      expect(_person(_annId), findsNothing);
    }, ready: _ready());
  });
}
