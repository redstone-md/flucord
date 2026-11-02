import 'dart:io';

import 'package:flucord/src/presentation/widgets/presence_indicator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/session_harness.dart';
import 'support/frame_times.dart';
import 'support/large_workspace.dart';

// Frame times of the whole app, in a real session over the fake wire, on a big
// made-up account. `tool/bench/README.md` says how to run this and how to read
// the result. `flutter test` does not run it, because a run takes minutes and
// the times mean nothing outside profile mode.
//
// A scenario looks for a widget only now and then while it records, because
// each search walks the whole widget tree on the UI thread.

/// How long a stream of events runs. At 60 frames a second, this leaves about 12
/// frames above p99.
const _streamSeconds = 20;

/// Records [action] under the scenario's name.
typedef _Measure = Future<void> Function(Future<void> Function() action);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Draws what the app asks for, on the display's own beat. Under this policy
  // `tester.pump` draws nothing. It only waits, so the frames are the app's own.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;

  final scenarios = <String, Object>{};
  final view = PlatformDispatcher.instance.implicitView!;
  binding.reportData = {
    'platform': Platform.operatingSystem,
    'os': Platform.operatingSystemVersion,
    'processors': Platform.numberOfProcessors,
    'view':
        '${view.physicalSize.width.round()}x${view.physicalSize.height.round()}',
    'scenarios': scenarios,
  };

  final ready = largeReady();
  final supplemental = largeSupplemental();

  /// One scenario in its own session: a fresh app that has reached the big
  /// account's first screen. Heavy test work must stay out of `measure`.
  void scenario(
    String name,
    Future<void> Function(
      WidgetTester tester,
      SessionHarness session,
      SyntheticTraffic traffic,
      _Measure measure,
    )
    body,
  ) {
    testSession(name, measured: true, ready: ready, (tester, session) async {
      expect(
        kProfileMode,
        isTrue,
        reason:
            'Times mean nothing outside profile mode. See tool/bench/README.md.',
      );
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('space-${SessionHarness.guildId}'))
            .evaluate()
            .isNotEmpty,
        'the first workspace',
      );
      await session.dispatch('READY_SUPPLEMENTAL', supplemental);
      await body(tester, session, SyntheticTraffic(), (action) async {
        scenarios[name] = await recordFrames(action);
      });
    });
  }

  scenario('scroll 500 messages', (tester, session, traffic, measure) async {
    final (oldest, newest) = traffic.routeHistory(
      session.transport,
      SessionHarness.channelId,
      count: 500,
    );
    await _openMainChannel(tester, session);
    await _until(
      tester,
      () => session.messageRow(newest).evaluate().isNotEmpty,
      'the newest message',
    );
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      wheel.hover(tester.getCenter(session.messageRow(newest))),
    );

    await measure(() async {
      // A wheel turning steadily, which loads the older pages as it goes, until
      // the first message of the channel is on screen.
      await _until(
        tester,
        () => session.messageRow(oldest).evaluate().isNotEmpty,
        'the oldest message',
        pollEvery: const Duration(milliseconds: 500),
        limit: const Duration(minutes: 3),
        whileWaiting: () async {
          for (var tick = 0; tick < 30; tick++) {
            await tester.sendEventToBinding(wheel.scroll(const Offset(0, -40)));
            await tester.pump(const Duration(milliseconds: 16));
          }
        },
      );
    });
  });

  scenario('switch channel', (tester, session, traffic, measure) async {
    final newestOf = {
      for (final id in const [
        SessionHarness.channelId,
        SessionHarness.otherChannelId,
      ])
        id: traffic.routeHistory(session.transport, id, count: 100).$2,
    };
    await _openMainChannel(tester, session);
    await _until(
      tester,
      () => session
          .messageRow(newestOf[SessionHarness.channelId]!)
          .evaluate()
          .isNotEmpty,
      'the first channel',
    );

    await measure(() async {
      for (var turn = 0; turn < 20; turn++) {
        final id = turn.isEven
            ? SessionHarness.otherChannelId
            : SessionHarness.channelId;
        await tester.tap(find.byKey(ValueKey('channel-$id')));
        await _until(
          tester,
          () => session.messageRow(newestOf[id]!).evaluate().isNotEmpty,
          'channel $id',
        );
        await tester.pump(const Duration(milliseconds: 500));
      }
    });
  });

  scenario('append in the active channel', (
    tester,
    session,
    traffic,
    measure,
  ) async {
    await _openMainChannel(tester, session);
    var last = '';

    await measure(() async {
      await _stream(
        perSecond: 10,
        send: () {
          final message = traffic.message(SessionHarness.channelId);
          last = message['id']! as String;
          session.dispatch('MESSAGE_CREATE', message, settle: false);
        },
      );
    });

    await _until(
      tester,
      () => session.messageRow(last).evaluate().isNotEmpty,
      'the last message',
    );
  });

  for (final perSecond in const [100, 500]) {
    scenario('$perSecond presences per second', (
      tester,
      session,
      traffic,
      measure,
    ) async {
      await _openMainChannel(tester, session);

      await measure(() async {
        await _stream(
          perSecond: perSecond,
          send: () => session.dispatch(
            'PRESENCE_UPDATE',
            traffic.presence(),
            settle: false,
          ),
        );
      });

      // The stream reached the app if one last change reaches the member list.
      await session.dispatch(
        'PRESENCE_UPDATE',
        traffic.presenceOf(
          visibleMemberId,
          guildId: SessionHarness.guildId,
          status: 'dnd',
        ),
      );
      await _until(
        tester,
        () =>
            tester
                .widget<PresenceIndicator>(
                  find
                      .byKey(ValueKey('member-presence-$visibleMemberId'))
                      .first,
                )
                .presence
                .displayStatus
                .label ==
            'Do Not Disturb',
        'the last presence',
      );
    });
  }

  scenario('reconnect with 5000 channels', (
    tester,
    session,
    traffic,
    measure,
  ) async {
    await _openMainChannel(tester, session);
    const renamed = 'general-after-reconnect';
    // The encoding is the test's own work, so it stays out of the recording.
    final readyFrame = session.encodeDispatch(
      'READY',
      largeReady(activeChannelName: renamed),
    );
    final supplementalFrame = session.encodeDispatch(
      'READY_SUPPLEMENTAL',
      supplemental,
    );

    await measure(() async {
      final dialled = session.sockets.length;
      await session.socket.dropConnection(code: 1006);
      await _until(
        tester,
        () => session.sockets.length > dialled,
        'a new socket',
      );
      await session.hello();
      // Discord no longer knows the session, so the client identifies afresh.
      session.socket.receive(const {'op': 9, 'd': false});
      await _until(
        tester,
        () => session.socket.frames.any((frame) => frame['op'] == 2),
        'IDENTIFY',
      );
      session.socket.receiveRaw(readyFrame);
      session.socket.receiveRaw(supplementalFrame);
      await _until(
        tester,
        () => find.text(renamed).evaluate().isNotEmpty,
        'the channel READY renamed',
      );
      // Whatever the READY pass still has to do after the first sign of it.
      await tester.pump(const Duration(seconds: 2));
    });
  });
}

/// Opens the harness's main channel. `session.openChannel` waits a fixed time
/// that suits a small account under the fake clock. On this account, in real time,
/// the channel row can take longer to appear.
Future<void> _openMainChannel(
  WidgetTester tester,
  SessionHarness session,
) async {
  final row = find.byKey(const ValueKey('channel-${SessionHarness.channelId}'));
  await tester.tap(
    find.byKey(const ValueKey('space-${SessionHarness.guildId}')),
  );
  await _until(tester, () => row.evaluate().isNotEmpty, 'the channel row');
  await tester.tap(row);
  await session.settle();
}

/// Calls [send] [_streamSeconds] times [perSecond], at that rate in real time.
///
/// Each event gets its own turn of the event loop, as a websocket frame does, so
/// a frame can draw between two events. A late timer makes the next events
/// follow with no wait, which keeps the rate. An app that cannot keep up loses no
/// events: the stream just takes longer, and every run does the same work.
Future<void> _stream({
  required int perSecond,
  required void Function() send,
}) async {
  final clock = Stopwatch()..start();
  for (var sent = 0; sent < perSecond * _streamSeconds; sent++) {
    final dueAt = sent * Duration.microsecondsPerSecond ~/ perSecond;
    final wait = dueAt - clock.elapsedMicroseconds;
    await Future<void>.delayed(Duration(microseconds: wait < 0 ? 0 : wait));
    send();
  }
}

/// Waits in real time until [done]. A run that cannot reach its goal fails here
/// rather than report times for something that did not happen.
Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String what, {
  Duration pollEvery = const Duration(milliseconds: 100),
  Duration limit = const Duration(minutes: 1),
  Future<void> Function()? whileWaiting,
}) async {
  final clock = Stopwatch()..start();
  while (!done()) {
    if (clock.elapsed > limit) fail('Never saw $what, after $limit.');
    await (whileWaiting?.call() ?? tester.pump(pollEvery));
  }
}
