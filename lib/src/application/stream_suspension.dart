import 'stream_viewer_controller.dart';
import 'window_foreground.dart';

/// Suspends watched sessions while this client's window is out of the
/// foreground.
///
/// Two halves that have no business knowing about each other: the window is
/// the only thing that knows whether anybody is looking, and the viewer is
/// what stops drawing when nobody is. Joining them here rather than inside
/// either keeps the viewer free of the desktop seam and puts the rule where
/// a test can reach it (ADR-0003).
final class StreamSuspension {
  StreamSuspension({
    required WindowForeground foreground,
    required StreamViewerController viewer,
  }) : _foreground = foreground,
       _viewer = viewer {
    _foreground.addListener(_suspend);
  }

  final WindowForeground _foreground;
  final StreamViewerController _viewer;

  void dispose() => _foreground.removeListener(_suspend);

  /// Sending is never suspended, and neither is anything on Discord's side:
  /// only what this client draws for itself (ADR-0003).
  void _suspend() => _viewer.setSuspended(!_foreground.inForeground);
}
