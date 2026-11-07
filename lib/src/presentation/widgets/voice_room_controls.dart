import 'package:flutter/material.dart';

import '../../application/self_video_controller.dart';
import '../../application/voice_controller.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import 'voice_control.dart';

/// The Room's control row, one copy for the voice channel Room and the DM
/// call band so the two cannot drift apart.
///
/// It listens to [controller] and [camera] itself, so it stays current
/// wherever it sits.
/// Every icon button inside, the ones in [goLive] and [soundboard] too,
/// takes the row's button style from an [IconButtonTheme].
class VoiceRoomControls extends StatelessWidget {
  const VoiceRoomControls({
    required this.controller,
    this.camera,
    this.goLive,
    this.soundboard,
    super.key,
  });

  final VoiceController controller;

  /// The account's own camera. Its button shows only where the build can
  /// send one.
  final SelfVideoController? camera;

  /// The Stream control (Go Live), or null where there is none.
  final Widget? goLive;

  /// The soundboard button. Only a guild Room passes one.
  final Widget? soundboard;

  static const height = 72.0;
  static const _button = Size(44, 40);
  static const _hangUp = Size(56, 40);
  static const _iconSize = 18.0;
  static const _gap = 8.0;
  static const _groupGap = 24.0;
  static const _dangerFillAlpha = 0.14;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, camera]),
    builder: (context, _) {
      final surfaces = context.surfaces;
      final style = ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(_button),
        minimumSize: const WidgetStatePropertyAll(_button),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        iconSize: const WidgetStatePropertyAll(_iconSize),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStatePropertyAll(surfaces.quietFill),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: FlucordRadius.large),
        ),
      ).merge(Theme.of(context).iconButtonTheme.style);
      Widget control(String key, VoiceControl control) => IconButton(
        key: ValueKey(key),
        onPressed: control.onPressed,
        tooltip: control.tooltip,
        style: control.byServer
            ? IconButton.styleFrom(
                backgroundColor: surfaces.danger,
                foregroundColor: Theme.of(context).colorScheme.onError,
              )
            : control.danger
            ? IconButton.styleFrom(
                backgroundColor: surfaces.danger.withValues(
                  alpha: _dangerFillAlpha,
                ),
                foregroundColor: surfaces.danger,
              )
            : control.active
            ? IconButton.styleFrom(foregroundColor: surfaces.text)
            : null,
        icon: FlucordIcon(control.icon),
      );
      return SizedBox(
        height: height,
        // A narrow window shrinks the row rather than cutting a button off.
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: IconButtonTheme(
              data: IconButtonThemeData(style: style),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: _gap,
                children: [
                  control('voice-mute', VoiceControl.mute(controller)),
                  control('voice-deafen', VoiceControl.deafen(controller)),
                  const SizedBox(width: _groupGap - 2 * _gap),
                  if (camera case final camera? when camera.isSupported)
                    control('voice-camera', VoiceControl.camera(camera)),
                  ?goLive,
                  control('voice-activities', const VoiceControl.activities()),
                  ?soundboard,
                  const SizedBox(width: _groupGap - 2 * _gap),
                  IconButton(
                    key: const ValueKey('voice-disconnect'),
                    onPressed: controller.isConnected
                        ? controller.disconnect
                        : null,
                    tooltip: 'Disconnect',
                    style: IconButton.styleFrom(
                      fixedSize: _hangUp,
                      backgroundColor: surfaces.danger,
                      foregroundColor: FlucordFixedColors.onFill,
                    ),
                    icon: const FlucordIcon(FlucordIcons.hangUp),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
