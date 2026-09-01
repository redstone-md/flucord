import 'stream_viewer_controller.dart';
import 'window_visible.dart';

/// Suspends watched sessions while this client's window cannot be seen.
///
/// Two halves that have no business knowing about each other: the window is
/// the only thing that knows whether anything of it is left on screen, and
/// the viewer is what stops drawing when nothing is. Joining them here rather
/// than inside either keeps the viewer free of the desktop seam and puts the
/// rule where a test can reach it (ADR-0003).
///
/// Losing the focus is not enough to suspend: a viewer alt-tabbing to another
/// window is still watching, and stopping the picture for them reads as the
/// stream breaking. Only a window nothing of is on screen suspends.
final class StreamSuspension {
  StreamSuspension({
    required WindowVisible visible,
    required StreamViewerController viewer,
  }) : _visible = visible,
       _viewer = viewer {
    _visible.addListener(_suspend);
  }

  final WindowVisible _visible;
  final StreamViewerController _viewer;

  void dispose() => _visible.removeListener(_suspend);

  /// Sending is never suspended, and neither is anything on Discord's side:
  /// only what this client draws for itself (ADR-0003).
  void _suspend() => _viewer.setSuspended(!_visible.inView);
}
