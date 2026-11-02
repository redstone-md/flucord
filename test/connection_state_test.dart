import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';
import 'package:flucord/src/domain/discord_session.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/session_harness.dart';

const _reconnecting = 'Connection lost. Reconnecting...';
const _connecting = 'Connecting to Discord...';
const _offline = 'Not connected to Discord. New messages will not arrive.';
const _unreachable = 'Could not reach Discord. Check your connection.';
const _scanCaption = 'Scan this code with the Discord app on your phone.';
const _confirmCaption = 'Now confirm the sign-in on your phone.';
const _retry = ValueKey('disconnected-retry');
final _savedToken = SessionHarness.tokenOf(SessionHarness.currentUserId);

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
      expect(find.text(_connecting), findsOneWidget);

      await session.dispatch('READY', SessionHarness.defaultReady());

      expect(find.text(_connecting), findsNothing);
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
      expect((identify['d'] as Map)['token'], _savedToken);
      expect(find.text(_offline), findsNothing);
      expect(find.byTooltip('Connected to Discord'), findsOneWidget);
    });
  });

  group('a launch that cannot reach Discord', () {
    testSession(
      'shows the reason, and Retry connects with the saved session',
      (tester, session) async {
        expect(find.text(_unreachable), findsOneWidget);
        // What Discord answered stays on screen, for a bug report.
        expect(find.text('Unavailable'), findsOneWidget);
        expect(find.textContaining('transport'), findsNothing);
        expect(find.textContaining('Gateway'), findsNothing);
        expect(session.sockets, isEmpty);
        // Retry is the way back. No new sign-in starts on its own.
        expect(session.remoteAuth.starts, 0);
        expect(find.text('Sign in with QR code'), findsOneWidget);

        session.discordReachable();
        await tester.tap(find.byKey(_retry));
        await session.connectToReady(SessionHarness.defaultReady());

        final identify = session.socket.frames.firstWhere(
          (frame) => frame['op'] == 2,
        );
        expect((identify['d'] as Map)['token'], _savedToken);
        expect(find.text(_unreachable), findsNothing);
        expect(find.byKey(const ValueKey('account-panel')), findsOneWidget);
      },
      launch: SessionLaunch.unreachable,
    );

    testSession(
      'a Retry that fails again keeps the reason and the Retry',
      (tester, session) async {
        await tester.tap(find.byKey(_retry));
        // Frame by frame: the attempt must not flash another failure screen,
        // for as long as the lookup repeats on the 503.
        for (var frame = 0; frame < 130; frame++) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump(const Duration(milliseconds: 25));
          expect(find.text('Workspace did not open'), findsNothing);
        }

        expect(find.text(_unreachable), findsOneWidget);
        expect(find.byKey(_retry), findsOneWidget);
      },
      launch: SessionLaunch.unreachable,
    );
  });

  testSession(
    'a launch with a cache but no connection shows it offline, and Retry connects',
    (tester, session) async {
      await session.relaunchUnreachable();

      expect(find.byKey(const ValueKey('account-panel')), findsOneWidget);
      expect(find.text(_offline), findsOneWidget);

      session.discordReachable();
      await tester.tap(find.byKey(const ValueKey('connection-banner-retry')));
      await session.connectToReady(SessionHarness.defaultReady());

      expect(find.text(_offline), findsNothing);
      expect(find.byTooltip('Connected to Discord'), findsOneWidget);
    },
    onDisk: true,
  );

  group('a new user', () {
    testSession(
      'signs in from the first screen, with the QR captioned',
      (tester, session) async {
        expect(find.byKey(_retry), findsNothing);
        expect(find.textContaining('transport'), findsNothing);
        expect(find.byTooltip('Connected to Discord'), findsNothing);

        session.remoteAuth.add(const DiscordRemoteAuthQrReady('fingerprint'));
        await session.settle();

        expect(session.remoteAuth.starts, 1);
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text(_scanCaption), findsOneWidget);
        expect(find.text(_confirmCaption), findsNothing);

        session.remoteAuth.add(
          const DiscordRemoteAuthUserPending(username: 'friend'),
        );
        await session.settle();

        expect(find.text(_confirmCaption), findsOneWidget);
        expect(find.text('friend'), findsOneWidget);
        expect(find.text(_scanCaption), findsNothing);
        expect(find.byType(QrImageView), findsNothing);

        session.remoteAuth.add(
          DiscordRemoteAuthCompleted(DiscordDesktopUserSession(_savedToken)),
        );
        await session.connectToReady(SessionHarness.defaultReady());

        final identify = session.socket.frames.firstWhere(
          (frame) => frame['op'] == 2,
        );
        expect((identify['d'] as Map)['token'], _savedToken);
        expect(find.byKey(const ValueKey('account-panel')), findsOneWidget);
      },
      launch: SessionLaunch.signedOut,
    );

    testSession(
      'the sign-in screen fits a small window',
      (tester, session) async {
        session.remoteAuth.add(const DiscordRemoteAuthQrReady('fingerprint'));
        await session.settle();

        // An overflow fails any session test, so showing the caption is enough.
        expect(find.text(_scanCaption), findsOneWidget);
      },
      launch: SessionLaunch.signedOut,
      size: const Size(940, 400),
    );

    testSession(
      'a sign-in that fails to connect keeps its error and does not start over',
      (tester, session) async {
        session.discordUnreachable();
        session.remoteAuth.add(
          DiscordRemoteAuthCompleted(DiscordDesktopUserSession(_savedToken)),
        );
        await session.settleServerErrorRepeats();

        expect(find.text(_unreachable), findsOneWidget);
        expect(session.remoteAuth.starts, 1);
      },
      launch: SessionLaunch.signedOut,
    );
  });
}
