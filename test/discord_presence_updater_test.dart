import 'dart:async';

import 'package:flucord/src/data/discord/discord_presence_updater.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for `Timer` that fires only when the test says so.
///
/// The sliding window is twenty seconds wide; waiting it out for real would
/// make this file the slowest in the suite and would still not prove that the
/// deferred send carries the *newest* state rather than the one that was
/// blocked.
final class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool cancelled = false;

  void fire() {
    if (cancelled) return;
    cancelled = true;
    callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

final class _Harness {
  _Harness({this.established = true});

  final List<Map<String, Object?>> sent = [];
  final List<_ManualTimer> timers = [];
  DateTime now = DateTime.utc(2026, 7, 26, 12);
  bool established;

  late final DiscordPresenceUpdater updater = DiscordPresenceUpdater(
    send: sent.add,
    isSessionEstablished: () => established,
    clock: () => now,
    timerFactory: (delay, callback) {
      final timer = _ManualTimer(delay, callback);
      timers.add(timer);
      return timer;
    },
  );

  void advance(Duration span) => now = now.add(span);

  _ManualTimer? get pending =>
      timers.where((timer) => timer.isActive).cast<_ManualTimer?>().lastOrNull;
}

void main() {
  test('sends the first presence and nothing identical after it', () {
    final harness = _Harness();

    harness.updater
      ..update(const SelfPresence())
      ..update(const SelfPresence());

    expect(harness.sent, hasLength(1));
    expect(harness.sent.single['status'], 'online');
    expect(harness.updater.lastPayload, harness.sent.single);
  });

  test('sends again as soon as any key differs', () {
    final harness = _Harness();

    harness.updater
      ..update(const SelfPresence())
      ..update(const SelfPresence(status: Presence.idle, since: 5))
      ..update(const SelfPresence(status: Presence.idle, since: 5, afk: true));

    expect(harness.sent, hasLength(3));
    expect(harness.sent.last['afk'], isTrue);
  });

  test('holds everything back until the session exists', () {
    final harness = _Harness(established: false);

    harness.updater.update(const SelfPresence(status: Presence.doNotDisturb));
    expect(harness.sent, isEmpty);
    expect(harness.updater.desired!.status, Presence.doNotDisturb);

    harness
      ..established = true
      ..updater.sessionEstablished();

    expect(harness.sent, hasLength(1));
    expect(harness.sent.single['status'], 'dnd');
  });

  test('a resume re-asserts the same presence', () {
    final harness = _Harness();

    harness.updater
      ..update(const SelfPresence())
      ..forceUpdate();

    expect(harness.sent, hasLength(2));
  });

  test('a resume before anything was composed sends nothing', () {
    final harness = _Harness()..updater.forceUpdate();

    expect(harness.sent, isEmpty);

    final closed = _Harness(established: false)
      ..updater.update(const SelfPresence())
      ..updater.forceUpdate();
    expect(closed.sent, isEmpty);
  });

  test('caps the window at five frames and defers the sixth', () {
    final harness = _Harness();

    for (var index = 0; index < 6; index++) {
      harness.updater.update(SelfPresence(since: index));
    }

    expect(harness.sent, hasLength(5));
    expect(harness.pending, isNotNull);
    expect(
      harness.pending!.delay,
      DiscordPresenceUpdater.window,
      reason: 'the oldest slot expires a full window after it was taken',
    );
  });

  test('the deferred frame carries the newest state, not the blocked one', () {
    final harness = _Harness();

    for (var index = 0; index < 6; index++) {
      harness.updater.update(SelfPresence(since: index));
    }
    harness.updater.update(const SelfPresence(status: Presence.doNotDisturb));
    expect(harness.sent, hasLength(5));

    harness.advance(DiscordPresenceUpdater.window);
    harness.pending!.fire();

    expect(harness.sent, hasLength(6));
    expect(harness.sent.last['status'], 'dnd');
  });

  test('a fired timer with nothing pending sends nothing', () {
    final harness = _Harness();

    for (var index = 0; index < 6; index++) {
      harness.updater.update(SelfPresence(since: index));
    }
    final deferred = harness.pending!;
    harness.updater.reset();

    deferred.callback();
    expect(harness.sent, hasLength(5));
  });

  test('a new session forgets what was already sent', () {
    final harness = _Harness()..updater.update(const SelfPresence());
    expect(harness.sent, hasLength(1));

    harness.updater
      ..reset()
      ..update(const SelfPresence());

    expect(harness.sent, hasLength(2));
    expect(harness.updater.lastPayload, isNotNull);
  });

  test('disposing cancels a deferred send', () {
    final harness = _Harness();

    for (var index = 0; index < 6; index++) {
      harness.updater.update(SelfPresence(since: index));
    }
    final deferred = harness.pending!;
    harness.updater.dispose();

    expect(deferred.isActive, isFalse);
  });

  test('a slot freed by the passage of time is reused straight away', () {
    final harness = _Harness();

    for (var index = 0; index < 5; index++) {
      harness.updater.update(SelfPresence(since: index));
    }
    harness.advance(DiscordPresenceUpdater.window + const Duration(seconds: 1));
    harness.updater.update(const SelfPresence(status: Presence.idle));

    expect(harness.sent, hasLength(6));
    expect(harness.pending, isNull);
  });
}
