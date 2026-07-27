import 'package:flucord/src/data/discord/discord_idle_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime.utc(2026, 7, 26, 12);

DateTime _at(Duration offset) => _start.add(offset);

void main() {
  test('a fresh tracker is neither idle nor away', () {
    final tracker = DiscordIdleTracker(startedAt: _start);

    expect(tracker.isIdle, isFalse);
    expect(tracker.isAfk, isFalse);
    expect(tracker.idleSince, isNull);
    expect(tracker.afkTimeoutSeconds, 60);
  });

  test('goes AFK at the account timeout and idle at ten minutes', () {
    final tracker = DiscordIdleTracker(startedAt: _start);

    expect(tracker.evaluate(_at(const Duration(seconds: 30))), isFalse);
    expect(tracker.isAfk, isFalse);

    expect(tracker.evaluate(_at(const Duration(seconds: 61))), isTrue);
    expect(tracker.isAfk, isTrue);
    expect(tracker.isIdle, isFalse);

    expect(
      tracker.evaluate(_at(const Duration(minutes: 10, seconds: 1))),
      isTrue,
    );
    expect(tracker.isIdle, isTrue);
    // R07: `since` is the last input, not the moment idle began.
    expect(tracker.idleSince, _start.millisecondsSinceEpoch);
  });

  test('input clears both flags and moves the last-input stamp', () {
    final tracker = DiscordIdleTracker(startedAt: _start)
      ..evaluate(_at(const Duration(minutes: 11)));
    expect(tracker.isIdle, isTrue);

    expect(tracker.markActive(_at(const Duration(minutes: 12))), isTrue);
    expect(tracker.isIdle, isFalse);
    expect(tracker.isAfk, isFalse);
    expect(tracker.idleSince, isNull);
  });

  test('marks are throttled so a stream of pointer moves costs nothing', () {
    final tracker = DiscordIdleTracker(startedAt: _start)
      ..markActive(_at(const Duration(minutes: 1)));

    expect(
      tracker.markActive(_at(const Duration(minutes: 1, milliseconds: 100))),
      isFalse,
    );
    tracker.markActive(_at(const Duration(minutes: 1, milliseconds: 600)));
    // The accepted mark advanced the stamp, so ten minutes later is measured
    // from it rather than from the tracker's start.
    tracker.evaluate(_at(const Duration(minutes: 11, milliseconds: 100)));
    expect(tracker.isIdle, isFalse);
    tracker.evaluate(_at(const Duration(minutes: 11, milliseconds: 700)));
    expect(tracker.isIdle, isTrue);
    expect(
      tracker.idleSince,
      _at(const Duration(minutes: 1, milliseconds: 600)).millisecondsSinceEpoch,
    );
  });

  test('a mark that arrives out of order never rewinds the stamp', () {
    final tracker = DiscordIdleTracker(startedAt: _start)
      ..markActive(_at(const Duration(minutes: 5)))
      ..markActive(_at(const Duration(minutes: 1)));

    tracker.evaluate(_at(const Duration(minutes: 12)));
    expect(tracker.isIdle, isFalse);
    expect(tracker.isAfk, isTrue);
  });

  test('a locked screen is idle and away at once', () {
    final tracker = DiscordIdleTracker(startedAt: _start);

    expect(
      tracker.setBlocked(
        now: _at(const Duration(seconds: 5)),
        systemLocked: true,
      ),
      isTrue,
    );
    expect(tracker.isIdle, isTrue);
    expect(tracker.isAfk, isTrue);

    expect(
      tracker.setBlocked(
        now: _at(const Duration(seconds: 10)),
        systemLocked: false,
      ),
      isTrue,
      reason: 'unlocking clears idle, but the suspend marker keeps it away',
    );
    expect(tracker.isIdle, isFalse);
    expect(tracker.isAfk, isTrue);

    expect(tracker.markActive(_at(const Duration(seconds: 11))), isTrue);
    expect(tracker.isAfk, isFalse);
  });

  test('suspending stamps the marker exactly once', () {
    final tracker = DiscordIdleTracker(startedAt: _start)
      ..setBlocked(now: _at(const Duration(seconds: 1)), systemSuspended: true);

    expect(
      tracker.setBlocked(
        now: _at(const Duration(seconds: 2)),
        systemLocked: true,
      ),
      isFalse,
      reason: 'already blocked, so nothing changed',
    );

    tracker
      ..setBlocked(now: _at(const Duration(seconds: 3)), systemSuspended: false)
      ..setBlocked(now: _at(const Duration(seconds: 4)), systemLocked: false);
    expect(tracker.isIdle, isFalse);
  });

  test('a zero timeout means always away', () {
    final tracker = DiscordIdleTracker(startedAt: _start);

    expect(tracker.setAfkTimeoutSeconds(0, now: _start), isTrue);
    expect(tracker.isAfk, isTrue);
    expect(tracker.isIdle, isFalse);
  });

  test('a timeout beyond ten minutes is capped by the idle threshold', () {
    final tracker = DiscordIdleTracker(startedAt: _start)
      ..setAfkTimeoutSeconds(3600, now: _start);

    expect(tracker.evaluate(_at(const Duration(minutes: 9))), isFalse);
    expect(tracker.isAfk, isFalse);

    tracker.evaluate(_at(const Duration(minutes: 10, seconds: 1)));
    expect(tracker.isAfk, isTrue);
  });

  test('a negative timeout falls back to the proto default', () {
    final tracker = DiscordIdleTracker(startedAt: _start);

    expect(tracker.setAfkTimeoutSeconds(-5, now: _start), isFalse);
    expect(
      tracker.afkTimeoutSeconds,
      DiscordIdleTracker.defaultAfkTimeoutSeconds,
    );
  });

  test('re-applying the same timeout changes nothing', () {
    final tracker = DiscordIdleTracker(startedAt: _start);

    expect(tracker.setAfkTimeoutSeconds(60, now: _start), isFalse);
    expect(tracker.setAfkTimeoutSeconds(120, now: _start), isFalse);
    expect(tracker.afkTimeoutSeconds, 120);
  });
}
