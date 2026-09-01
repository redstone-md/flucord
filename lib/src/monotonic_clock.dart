/// A clock that only moves forward, for schedules and ages measured inside
/// the app. Wall-clock time jumps when the OS adjusts it; this never does.
Duration monotonicNow() => _clock.elapsed;

final Stopwatch _clock = Stopwatch()..start();
