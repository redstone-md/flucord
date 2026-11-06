import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_log.dart';
import '../../application/stream_viewer_controller.dart';
import '../../domain/go_live_stream.dart';
import '../../platform/window_full_screen.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import 'go_live_viewer.dart';

/// Shows a watched Stream full screen: the picture alone, on a route above
/// the app, with the window in full screen too where it can be.
///
/// It carries the viewer and the window itself because the route opens above
/// the app's scopes. Esc, the exit button or a double-click goes back. The
/// route follows the Watched session, not its pictures: it stays through a
/// reconnect or a decoder that drops for a moment, and closes by itself once
/// the session is gone, which covers Stop watching, the Stream ending, and
/// leaving the Room.
final class StreamFullScreen {
  const StreamFullScreen({required this.viewer, this.window});

  final StreamViewerController viewer;

  /// Null where the window cannot go full screen: the Stream then fills the
  /// window alone.
  final WindowFullScreen? window;

  /// Opens [key] full screen on [navigator], the app's root one, and returns
  /// once it has closed and the window has its size and place back.
  Future<void> open(NavigatorState navigator, GoLiveStreamKey key) async {
    if (!viewer.isOpen(key)) return;
    late final Route<void> route;
    route = PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, _, _) =>
          _StreamFullScreenPage(viewer: viewer, streamKey: key),
    );
    void closeWhenGone() {
      if (!viewer.isOpen(key) && route.isActive) {
        navigator.removeRoute(route);
      }
    }

    viewer.addListener(closeWhenGone);
    unawaited(_window((window) => window.enter()));
    try {
      await navigator.push(route);
    } finally {
      viewer.removeListener(closeWhenGone);
      await _window((window) => window.leave());
    }
  }

  /// A window that will not change is logged, not thrown: the Stream still
  /// fills the window.
  Future<void> _window(Future<void> Function(WindowFullScreen) change) async {
    final window = this.window;
    if (window == null) return;
    try {
      await change(window);
    } on Object catch (error) {
      AppLog.warning('stream.fullscreen', 'window refused', error: error);
    }
  }
}

class _StreamFullScreenPage extends StatelessWidget {
  const _StreamFullScreenPage({required this.viewer, required this.streamKey});

  final StreamViewerController viewer;
  final GoLiveStreamKey streamKey;

  @override
  Widget build(BuildContext context) {
    void close() => unawaited(Navigator.of(context).maybePop());
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: FlucordFixedColors.media,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The exit button sits beside this, not inside it, so its
              // press does not wait to learn whether a second click follows.
              GestureDetector(
                key: const ValueKey('stream-full-screen'),
                behavior: HitTestBehavior.opaque,
                onDoubleTap: close,
                // Rebuilt with the viewer: the session that carries the
                // pictures can arrive, or be replaced, while the page is up.
                child: ListenableBuilder(
                  listenable: viewer,
                  builder: (context, _) => GoLiveViewer(
                    textures: viewer.texturesFor(streamKey),
                    label: streamKey.userId,
                    error: viewer.errorFor(streamKey),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: SafeArea(
                  child: FullScreenButton(
                    key: const ValueKey('stream-full-screen-exit'),
                    isFullScreen: true,
                    onPressed: close,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The button that enters full screen on the Stage and leaves it on the
/// full-screen page.
class FullScreenButton extends StatelessWidget {
  const FullScreenButton({
    required this.isFullScreen,
    required this.onPressed,
    super.key,
  });

  final bool isFullScreen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    onPressed: onPressed,
    tooltip: isFullScreen ? 'Exit full screen' : 'Full screen',
    icon: FlucordIcon(
      isFullScreen ? FlucordIcons.exitFullscreen : FlucordIcons.fullscreen,
    ),
  );
}
