import 'package:flutter/material.dart';

import '../../application/go_live_controller.dart';
import '../../theme/flucord_theme.dart';
import 'flucord_dialog.dart';

/// Which screen to share.
///
/// No thumbnails. Building them means capturing each display, and Windows
/// allows one duplication of an output at a time — a preview held open is
/// exactly what refused the share that followed it. A list that works beats a
/// grid of pictures that costs the thing it is illustrating.
class GoLiveDisplayDialog extends StatelessWidget {
  const GoLiveDisplayDialog({required this.displays, super.key});

  final List<GoLiveDisplay> displays;

  /// Asks which of [displays] to share, answering null when dismissed. One
  /// screen is shared without asking.
  ///
  /// The displays come from the encoder, not from a capture library. WebRTC's
  /// enumeration opens duplications of its own to build thumbnails with, and
  /// Windows refuses a second duplication of a display something already
  /// holds, which is what turned every share into "that display is no longer
  /// attached".
  static Future<String?> pick(
    BuildContext context,
    List<GoLiveDisplay> displays,
  ) async {
    if (displays.length <= 1) return displays.firstOrNull?.sourceId;
    final picked = await showDialog<GoLiveDisplay>(
      context: context,
      builder: (_) => GoLiveDisplayDialog(displays: displays),
    );
    return picked?.sourceId;
  }

  @override
  Widget build(BuildContext context) => FlucordDialog(
    key: const ValueKey('go-live-display-dialog'),
    title: const Text('Share a screen'),
    content: SizedBox(
      width: 360,
      child: displays.isEmpty
          ? const Text('This machine reported no screen to capture.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final display in displays)
                  ListTile(
                    key: ValueKey('go-live-display-${display.index}'),
                    leading: Icon(
                      Icons.monitor_outlined,
                      color: context.surfaces.muted,
                    ),
                    title: Text(display.name),
                    onTap: () => Navigator.of(context).pop(display),
                  ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ],
  );
}
