import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/session_harness.dart';

const _reconnecting = 'Connection lost. Reconnecting...';
const _offline = 'Not connected to Discord. New messages will not arrive.';

void main() {
  group('while a session runs', () {
    testSession('a successful resume reads as connected', (
      tester,
      session,
    ) async {
      expect(find.byTooltip('Connected to Discord'), findsOneWidget);
      expect(find.text(_reconnecting), findsNothing);

      await session.socket.dropConnection(code: 1006);
      await tester.pump(const Duration(seconds: 2));
      await session.settle();
      await session.hello();
      expect(session.socket.frames.map((frame) => frame['op']), contains(6));

      expect(find.byTooltip('Reconnecting to Discord'), findsOneWidget);
      expect(find.text(_reconnecting), findsOneWidget);

      await session.dispatch('RESUMED', {});

      expect(find.byTooltip('Connected to Discord'), findsOneWidget);
      expect(find.text(_reconnecting), findsNothing);
    });

    testSession('the banner stays up when a session has to start over', (
      tester,
      session,
    ) async {
      // Discord drops the session, then the socket goes before a new READY.
      session.socket.receive({'op': 9, 'd': false});
      await session.settle();
      await session.socket.dropConnection(code: 1006);
      await session.settle();
      expect(find.text(_reconnecting), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await session.settle();
      await session.hello();
      expect(session.socket.frames.map((frame) => frame['op']), contains(2));
      expect(find.text(_reconnecting), findsOneWidget);

      await session.dispatch('READY', SessionHarness.defaultReady());

      expect(find.text(_reconnecting), findsNothing);
    });

    testSession('offline shows Retry, which connects with the saved session', (
      tester,
      session,
    ) async {
      expect(find.text(_offline), findsNothing);

      await session.socket.dropConnection(code: 4004);
      await session.settle();

      expect(find.text(_offline), findsOneWidget);
      expect(find.byTooltip('Not connected to Discord'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('connection-banner-retry')));
      await session.connectToReady(SessionHarness.defaultReady());

      final identify = session.socket.frames.firstWhere(
        (frame) => frame['op'] == 2,
      );
      expect((identify['d'] as Map)['token'], 'harness-token');
      expect(find.text(_offline), findsNothing);
      expect(find.byTooltip('Connected to Discord'), findsOneWidget);
    });
  });
}
