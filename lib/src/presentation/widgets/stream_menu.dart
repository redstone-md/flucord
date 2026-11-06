import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/stream_viewer_controller.dart';
import '../../application/voice_controller.dart';
import '../../domain/go_live_stream.dart';
import '../../theme/flucord_icons.dart';
import 'context_menu_target.dart';
import 'flucord_menu.dart';
import 'popup_anchor.dart';
import 'stream_full_screen.dart';

/// Flucord's menu for one Stream: what a right click on a Stream tile or on
/// the watched Stage opens.
///
/// It carries the controllers itself because the menu opens on a route above
/// the app's scopes. Stream volume and Mute stream are kept per Sender, so
/// they show whether or not the Stream is watched; Full screen shows only
/// while it is.
final class StreamMenu {
  const StreamMenu({
    required this.voice,
    required this.viewer,
    required this.fullScreen,
    required this.streamKeyFor,
    required this.onToggleWatch,
  });

  final VoiceController voice;
  final StreamViewerController viewer;
  final StreamFullScreen fullScreen;

  /// The key of [sender]'s Stream in the Room on screen.
  final GoLiveStreamKey Function(String sender) streamKeyFor;

  /// Watches [sender]'s Stream, or stops watching it: the same path as the
  /// tile's own Watch button.
  final ValueChanged<String> onToggleWatch;

  /// Opens the menu for [sender]'s Stream from the widget at [context], at
  /// [position] in global coordinates, or in the widget's middle when null.
  Future<void> open(
    BuildContext context,
    String sender, {
    Offset? position,
  }) async {
    final key = streamKeyFor(sender);
    final watching = viewer.isWatching(key);
    final open = viewer.isOpen(key);
    final chosen = await showMenu<VoidCallback>(
      context: context,
      position: menuAt(context, position: position),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
      items: [
        if (watching) ...[
          flucordMenuAction(
            'stream-menu-full-screen',
            'Full screen',
            FlucordIcons.fullscreen,
            () => unawaited(fullScreen.open(context, key)),
          ),
          const FlucordMenuDivider(),
        ],
        FlucordMenuSlider(
          key: const ValueKey('stream-menu-volume'),
          label: 'Stream volume',
          value: voice.streamVolumeFor(sender),
          onChanged: (level) => unawaited(voice.setStreamVolume(sender, level)),
        ),
        const FlucordMenuDivider(),
        FlucordMenuCheckbox(
          key: const ValueKey('stream-menu-mute'),
          label: 'Mute stream',
          value: voice.isStreamMuted(sender),
          onChanged: (muted) => unawaited(voice.setStreamMuted(sender, muted)),
        ),
        const FlucordMenuDivider(),
        flucordMenuAction(
          open ? 'stream-menu-stop-watching' : 'stream-menu-watch',
          open ? 'Stop watching' : 'Watch stream',
          open ? FlucordIcons.stop : FlucordIcons.streaming,
          () => onToggleWatch(sender),
          danger: open,
        ),
      ],
    );
    chosen?.call();
  }
}

/// A watched Stream on the Stage: right-click for the Stream menu,
/// double-click or the corner button for full screen.
class StageStream extends StatelessWidget {
  const StageStream({
    required this.sender,
    required this.menu,
    required this.child,
    super.key,
  });

  final String sender;
  final StreamMenu menu;

  /// The Stream's picture.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void fullScreen() =>
        unawaited(menu.fullScreen.open(context, menu.streamKeyFor(sender)));
    // The button sits beside the picture's gestures, not inside them, so
    // its press does not wait to learn whether a second click follows.
    return Stack(
      fit: StackFit.expand,
      children: [
        ContextMenuTarget(
          key: const ValueKey('stage-stream'),
          onOpen: (context, position) =>
              unawaited(menu.open(context, sender, position: position)),
          // No single tap here, so a double-click costs the Stage no delay.
          onDoubleTap: fullScreen,
          builder: (_, _) => child,
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: FullScreenButton(
            key: const ValueKey('stage-stream-full-screen'),
            isFullScreen: false,
            onPressed: fullScreen,
          ),
        ),
      ],
    );
  }
}
