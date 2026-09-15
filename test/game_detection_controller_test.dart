import 'dart:async';

import 'package:flucord/src/application/game_detection_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/game_detection.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final _drgId = '999999999999999999';

/// A source whose answers a test sets per round.
final class _FakeSource implements GameDetectionSource {
  Set<String> running = {};
  List<DetectableGame>? games;
  int scans = 0;

  @override
  Future<Set<String>> runningExecutables() async {
    scans++;
    return running;
  }

  @override
  Future<List<DetectableGame>?> detectableGames() async => games;
}

/// A presence plane recording the local-activity publishes.
final class _FakePresence implements PresenceService {
  final List<List<UserActivity>> published = [];
  @override
  bool canEdit = true;

  @override
  SelfPresence selfPresence = const SelfPresence();

  @override
  Presence chosenStatus = Presence.online;

  @override
  UserActivity? get customStatus => null;

  @override
  List<UserSession> get sessions => const [];

  @override
  Stream<SelfPresence> get selfPresenceUpdates =>
      const Stream<SelfPresence>.empty();

  @override
  List<UserActivity> get localActivities =>
      published.isEmpty ? const [] : published.last;

  @override
  Future<void> setLocalActivities(List<UserActivity> activities) async {
    published.add(List.of(activities));
  }

  @override
  Future<void> setStatus(Presence status) async {}

  @override
  Future<void> setCustomStatus({
    String text = '',
    String emojiName = '',
    CustomStatusDuration expiry = CustomStatusDuration.never,
  }) async {}

  @override
  void markActive() {}
}

/// Timer ticks a test fires by hand, so the cadence is observed, not waited
/// on.
final class _TimerHarness {
  _TimerHarness() {
    controller = GameDetectionController(
      presenceProvider: () => presence,
      sourceProvider: () => source,
      showsCurrentGame: () => showsCurrentGame,
      timerFactory: (interval, callback) {
        late final _FakeTimer timer;
        timer = _FakeTimer(() => callback(timer));
        lastCallback = timer.fire;
        return timer;
      },
    );
  }

  final _FakePresence presence = _FakePresence();
  final _FakeSource source = _FakeSource();
  bool showsCurrentGame = true;
  late final GameDetectionController controller;
  void Function()? lastCallback;

  /// Fires the periodic tick, the way the real timer would.
  Future<void> tick() async {
    lastCallback!();
    await pumpEventQueue();
  }
}

final class _FakeTimer implements Timer {
  _FakeTimer(this.fire);

  final void Function() fire;
  bool _cancelled = false;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 0;
}

void main() {
  test('a running game is published as the playing activity', () async {
    final harness = _TimerHarness();
    harness.source.running = {'fsd-win64-shipping.exe'};
    harness.source.games = [
      DetectableGame(
        id: _drgId,
        name: 'Deep Rock Galactic',
        executables: ['FSD-Win64-Shipping.exe'],
      ),
    ];
    harness.controller.reconcile();
    await harness.controller.detect();

    final published = harness.presence.published.single;
    expect(published, hasLength(1));
    expect(published.single.name, 'Deep Rock Galactic');
    expect(published.single.type, ActivityType.playing);
    expect(published.single.applicationId, _drgId);
    expect(harness.controller.activity!.name, 'Deep Rock Galactic');
    harness.controller.dispose();
  });

  test('the show-current-game setting off clears what was published', () async {
    final harness = _TimerHarness();
    harness.source.running = {'game.exe'};
    harness.source.games = [
      DetectableGame(id: _drgId, name: 'The Game', executables: ['game.exe']),
    ];
    harness.controller.reconcile();
    await harness.controller.detect();
    expect(harness.presence.published.single, hasLength(1));

    harness.showsCurrentGame = false;
    await harness.controller.detect();

    expect(harness.presence.published.last, isEmpty);
    expect(harness.controller.activity, isNull);
    harness.controller.dispose();
  });

  test('nothing running clears a previously published game', () async {
    final harness = _TimerHarness();
    harness.source.running = {'game.exe'};
    harness.source.games = [
      DetectableGame(id: _drgId, name: 'The Game', executables: ['game.exe']),
    ];
    harness.controller.reconcile();
    await harness.controller.detect();

    harness.source.running = {};
    await harness.controller.detect();

    expect(harness.presence.published.last, isEmpty);
    expect(harness.controller.activity, isNull);
    harness.controller.dispose();
  });

  test('a transport with no presence plane publishes nothing', () async {
    final presence = _FakePresence();
    final source = _FakeSource()
      ..running = {'game.exe'}
      ..games = [
        DetectableGame(id: _drgId, name: 'The Game', executables: ['game.exe']),
      ];
    final controller = GameDetectionController(
      presenceProvider: () => null,
      sourceProvider: () => source,
      showsCurrentGame: () => true,
    );
    addTearDown(controller.dispose);

    controller.reconcile();
    expect(controller.isAvailable, isFalse);
    await controller.detect();

    expect(presence.published, isEmpty);
  });

  test('a source that cannot read the list publishes nothing', () async {
    final harness = _TimerHarness();
    harness.source.running = {'game.exe'};
    harness.source.games = null;
    harness.controller.reconcile();
    await harness.controller.detect();

    expect(harness.presence.published.single, isEmpty);
    expect(harness.controller.activity, isNull);
    harness.controller.dispose();
  });

  test('the periodic scan drives rounds until it is stopped', () async {
    final harness = _TimerHarness();
    harness.source.running = {'game.exe'};
    harness.source.games = [
      DetectableGame(id: _drgId, name: 'The Game', executables: ['game.exe']),
    ];
    harness.controller.reconcile();
    harness.controller.startScanning();
    await pumpEventQueue();
    expect(harness.source.scans, 1);

    await harness.tick();
    expect(harness.source.scans, 2);

    harness.controller.stopScanning();
    await harness.tick();
    expect(harness.source.scans, 2);
    harness.controller.dispose();
  });

  test('a failed round reports itself and keeps what was published', () async {
    final harness = _TimerHarness();
    harness.source.running = {'game.exe'};
    harness.source.games = [
      DetectableGame(id: _drgId, name: 'The Game', executables: ['game.exe']),
    ];
    harness.controller.reconcile();
    await harness.controller.detect();
    final before = harness.presence.published.length;

    final failing = GameDetectionController(
      presenceProvider: () => harness.presence,
      sourceProvider: () => _FailingSource(),
      showsCurrentGame: () => true,
    );
    addTearDown(failing.dispose);
    failing.reconcile();
    await failing.detect();

    expect(failing.error, isNotNull);
    expect(harness.presence.published.length, before);
  });

  test(
    'a session switch detaches the activity from the old transport',
    () async {
      final harness = _TimerHarness();
      harness.source.running = {'game.exe'};
      harness.source.games = [
        DetectableGame(id: _drgId, name: 'The Game', executables: ['game.exe']),
      ];
      harness.controller.reconcile();
      await harness.controller.detect();
      expect(harness.controller.activity, isNotNull);

      // A sign-in replaces the transport: the same provider now answers with
      // a new plane and a new source, which is what reconcile reads.
      final nextPresence = _FakePresence();
      final nextSource = _FakeSource();
      final switched = GameDetectionController(
        presenceProvider: () => nextPresence,
        sourceProvider: () => nextSource,
        showsCurrentGame: () => true,
      );
      addTearDown(switched.dispose);
      switched.reconcile();

      expect(switched.activity, isNull);
      expect(nextPresence.published, isEmpty);
      harness.controller.dispose();
    },
  );

  test('the setting gate is read live on every round', () async {
    final harness = _TimerHarness();
    harness.source.running = {'game.exe'};
    harness.source.games = [
      DetectableGame(id: _drgId, name: 'The Game', executables: ['game.exe']),
    ];
    harness.controller.reconcile();
    harness.controller.startScanning();
    await pumpEventQueue();
    expect(harness.presence.published.single, hasLength(1));

    harness.showsCurrentGame = false;
    await harness.tick();
    expect(harness.presence.published.last, isEmpty);
    harness.controller.dispose();
  });
}

/// A source whose every answer fails, for the failure path.
final class _FailingSource implements GameDetectionSource {
  @override
  Future<Set<String>> runningExecutables() async {
    throw StateError('scan refused');
  }

  @override
  Future<List<DetectableGame>?> detectableGames() async => null;
}
