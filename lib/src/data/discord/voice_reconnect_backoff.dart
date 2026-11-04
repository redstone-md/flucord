import 'dart:math';

/// How long a dropped voice socket waits before it dials again, and when it
/// stops dialling.
///
/// Each wait is double the one before, from [firstDelay] up to [maxDelay], as
/// Discord's own client backs off its voice socket. Up to a quarter of each
/// wait is taken off at random, so clients that dropped together do not all
/// dial again at the same moment. After [maxAttempts] waits [next] answers
/// null and the connection gives up. A connection that comes back calls
/// [reset], so the next outage gets every attempt again.
final class VoiceReconnectBackoff {
  /// [jitter] answers a number from 0 up to (not including) 1. Tests pass a
  /// fixed one so every wait is exact.
  VoiceReconnectBackoff({
    this.firstDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 6,
    double Function()? jitter,
  }) : assert(firstDelay <= maxDelay, 'the first wait is above the cap'),
       _jitter = jitter ?? Random().nextDouble,
       _ceiling = firstDelay;

  final Duration firstDelay;
  final Duration maxDelay;
  final int maxAttempts;
  final double Function() _jitter;

  /// The share of a wait that jitter can take off.
  static const _jitterShare = 0.25;

  int _attempts = 0;

  /// The wait for the next attempt before jitter.
  Duration _ceiling;

  /// The wait before the next attempt, or null once every attempt is spent.
  Duration? next() {
    if (_attempts >= maxAttempts) return null;
    _attempts++;
    final wait = _ceiling;
    final doubled = _ceiling * 2;
    _ceiling = doubled < maxDelay ? doubled : maxDelay;
    return wait * (1 - _jitterShare * _jitter());
  }

  void reset() {
    _attempts = 0;
    _ceiling = firstDelay;
  }
}
