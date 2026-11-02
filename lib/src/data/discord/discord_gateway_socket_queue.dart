import 'dart:async';
import 'dart:collection';

/// Runs what one socket reports in the order the socket reported it.
///
/// A step runs at once when nothing is ahead of it, so ordinary traffic takes
/// no extra turn of the event loop. A step that returns a future, which is a
/// large frame on its way through a worker isolate, holds every later step until
/// the future ends. That includes the socket's own end, so a frame that arrived
/// before a close is handled before the close.
final class DiscordGatewaySocketQueue {
  final Queue<FutureOr<void> Function()> _steps = ListQueue();
  bool _held = false;

  void add(FutureOr<void> Function() step) {
    _steps.add(step);
    if (!_held) _runSteps();
  }

  void _runSteps() {
    while (_steps.isNotEmpty) {
      final result = _steps.removeFirst()();
      if (result is Future<void>) {
        _held = true;
        unawaited(
          result.whenComplete(() {
            _held = false;
            _runSteps();
          }),
        );
        return;
      }
    }
  }
}
