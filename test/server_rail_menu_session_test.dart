import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/channel_history_fixture.dart';
import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

final _server = find.byKey(const ValueKey('space-${SessionHarness.guildId}'));
final _home = find.byKey(const ValueKey('space-direct-messages'));
final _markRead = find.byKey(const ValueKey('server-menu-mark-read'));
final _leave = find.byKey(const ValueKey('leave-server'));
final _notifications = find.byKey(const ValueKey('space-notification-menu'));

Future<void> _rightClick(
  WidgetTester tester,
  SessionHarness session,
  Finder target,
) async {
  final mouse = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await mouse.up();
  await session.settle();
}

void main() {
  testSession(
    'right-clicking a server marks it read from the menu',
    (tester, session) async {
      await _rightClick(tester, session, _server);

      await tester.tap(_markRead);
      await session.settle();

      expect(
        session.transport.requests.where(
          (request) =>
              request.method == 'POST' &&
              request.uri.path == '/api/v9/read-states/ack-bulk',
        ),
        hasLength(1),
      );
    },
    ready: ChannelHistoryFixture.readyWithUnread(firstUnread: 5, newest: 9),
    routes: (transport) => transport.on(
      'POST',
      '/api/v9/read-states/ack-bulk',
      (_) => jsonResponse(null, statusCode: 204),
    ),
    platform: TargetPlatform.windows,
  );

  testSession(
    'the menu acts on the server clicked, not the one on screen',
    (tester, session) async {
      await _rightClick(tester, session, _server);

      await tester.tap(_leave);
      await session.settle();

      expect(find.text('Leave The Forge?'), findsOneWidget);
    },
    platform: TargetPlatform.windows,
  );

  testSession(
    'Notification settings changes that server, from any other space',
    (tester, session) async {
      await _rightClick(tester, session, _server);

      // The last match is the menu row: the direct messages header on screen
      // has a button with the same key.
      await tester.tap(_notifications.last);
      await session.settle();
      await tester.tap(find.text('Only @mentions'));
      await session.settle();

      final change = session.transport.requests.singleWhere(
        (request) => request.method == 'PATCH',
      );
      expect(change.uri.path, '/api/v9/users/@me/guilds/settings');
      expect(
        (change.json! as Map)['guilds'],
        contains(SessionHarness.guildId),
      );
    },
    platform: TargetPlatform.windows,
  );

  testSession(
    'the direct messages button has no server menu',
    (tester, session) async {
      await _rightClick(tester, session, _home);

      expect(_leave, findsNothing);
      expect(_markRead, findsNothing);
    },
    platform: TargetPlatform.windows,
  );
}
