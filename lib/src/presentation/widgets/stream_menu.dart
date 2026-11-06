import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/stream_viewer_controller.dart';
import '../../application/voice_controller.dart';
import '../../domain/go_live_stream.dart';
import '../../theme/flucord_icons.dart';
import 'flucord_menu.dart';
import 'popup_anchor.dart';
import 'stream_full_screen.dart';

/// Flucord's menu for one Stream: what a right click on a Stream tile or on
/// the watched Stage opens.
///
/// It carries the controllers itself because the menu opens on a route above
/// the app's scopes. Stream volume and Mute stream are kept per Sender, so
/// they show whether or not the Stream is watched; Full screen shows only
/// while its Watched session is open, pictures or not.
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
    final open = viewer.isOpen(key);
    final chosen = await showMenu<VoidCallback>(
      context: context,
      position: menuAt(context, position: position),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
      items: [
        if (open) ...[
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
