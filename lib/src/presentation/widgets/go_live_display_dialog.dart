import 'package:flutter/material.dart';

import '../../application/go_live_controller.dart';
import '../../theme/flucord_theme.dart';

/// Which screen to share.
///
/// No thumbnails. Building them means capturing each display, and Windows
/// allows one duplication of an output at a time — a preview held open is
/// exactly what refused the share that followed it. A list that works beats a
/// grid of pictures that costs the thing it is illustrating.
class GoLiveDisplayDialog extends StatelessWidget {
  const GoLiveDisplayDialog({required this.displays, super.key});

  final List<GoLiveDisplay> displays;

  @override
  Widget build(BuildContext context) => AlertDialog(
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
