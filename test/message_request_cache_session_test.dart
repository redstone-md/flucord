import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/session_harness.dart';

const _requestId = '400000000000000021';
const _strangerId = '500000000000000021';

Finder _dmRow(String id) => find.byKey(ValueKey('channel-$id'));

Finder _requestRow(String id) => find.byKey(ValueKey('request-$id'));

/// The default READY, plus a DM from a stranger that is [pending] a request.
Map<String, Object?> _readyWithRequest({required bool pending}) {
  final ready = SessionHarness.defaultReady();
  ready['users'] = [
    ...ready['users']! as List,
    {'id': _strangerId, 'username': 'stranger', 'global_name': 'Stranger'},
  ];
  ready['private_channels'] = [
    ...ready['private_channels']! as List,
    {
      'id': _requestId,
      'type': 1,
      'recipient_ids': [_strangerId],
      if (pending) ...{
        'is_message_request': true,
        'is_message_request_timestamp': '2026-11-03T18:30:00Z',
      },
    },
  ];
  return ready;
}

Future<void> _openRequestsFolder(
  WidgetTester tester,
  SessionHarness session,
) async {
  await tester.tap(find.byKey(const ValueKey('message-requests-folder')));
  await session.settle();
}

void main() {
  testSession(
    'an offline launch keeps a pending request in the requests folder',
    (tester, session) async {
      await session.relaunchUnreachable();

      expect(_dmRow(_requestId), findsNothing);
      await _openRequestsFolder(tester, session);
      expect(_requestRow(_requestId), findsOneWidget);
    },
    ready: _readyWithRequest(pending: true),
    onDisk: true,
  );

  testSession(
    'a request accepted while offline moves to the DM list on reconnect',
    (tester, session) async {
      session.socket.receive(const {'op': 9, 'd': false});
      await session.settle();
      await session.dispatch('READY', _readyWithRequest(pending: false));

      expect(_dmRow(_requestId), findsOneWidget);
      expect(
        find.byKey(const ValueKey('message-requests-folder')),
        findsNothing,
      );
    },
    ready: _readyWithRequest(pending: true),
  );
}
