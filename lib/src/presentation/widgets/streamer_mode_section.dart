import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/streamer_mode_controller.dart';
import '../../theme/flucord_theme.dart';

/// Streamer mode's switches.
///
/// All six of Discord's, and each one does something: a switch that changed
/// nothing would be worse here than anywhere else in the client, because
/// believing something is hidden is the whole point.
class StreamerModeSection extends StatelessWidget {
  const StreamerModeSection({required this.controller, super.key});

  final StreamerModeController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final settings = controller.settings;
      return Column(
        key: const ValueKey('streamer-mode-section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const ValueKey('streamer-mode-enabled'),
            contentPadding: EdgeInsets.zero,
            value: settings.enabled,
            onChanged: (value) =>
                unawaited(controller.setEnabled(enabled: value)),
            title: const Text('Streamer mode', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              'On right now. Turning it on by hand keeps it on after a '
              'stream ends.',
              style: TextStyle(fontSize: 11, color: context.surfaces.muted),
            ),
          ),
          SwitchListTile(
            key: const ValueKey('streamer-mode-automatic'),
            contentPadding: EdgeInsets.zero,
            value: settings.automatic,
            onChanged: (value) =>
                unawaited(controller.setAutomatic(automatic: value)),
            title: const Text(
              'Enable automatically',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              'Turns on when this client starts a stream, and off again '
              'when it stops.',
              style: TextStyle(fontSize: 11, color: context.surfaces.muted),
            ),
          ),
          const Divider(height: 24),
          _Switch(
            switchKey: const ValueKey('streamer-mode-personal'),
            title: 'Hide personal information',
            subtitle: 'Blanks your name in the account panel.',
            value: settings.hidePersonalInformation,
            onChanged: (value) =>
                controller.setHidePersonalInformation(hide: value),
          ),
          _Switch(
            switchKey: const ValueKey('streamer-mode-invites'),
            title: 'Hide invite links',
            subtitle: 'Replaces invites in messages with a placeholder.',
            value: settings.hideInviteLinks,
            onChanged: (value) => controller.setHideInviteLinks(hide: value),
          ),
          _Switch(
            switchKey: const ValueKey('streamer-mode-sounds'),
            title: 'Disable sounds',
            subtitle: 'Soundboard effects are still listed, not played.',
            value: settings.disableSounds,
            onChanged: (value) => controller.setDisableSounds(disable: value),
          ),
          _Switch(
            switchKey: const ValueKey('streamer-mode-notifications'),
            title: 'Disable notifications',
            subtitle: 'No desktop toasts while the mode is on.',
            value: settings.disableNotifications,
            onChanged: (value) =>
                controller.setDisableNotifications(disable: value),
          ),
          _Switch(
            switchKey: const ValueKey('streamer-mode-overlay'),
            title: 'Hide the in-game overlay',
            subtitle: 'It is drawn over whatever is being captured, so '
                'hiding the client window does not cover it.',
            value: settings.hideOverlayWidgets,
            onChanged: (value) =>
                controller.setHideOverlayWidgets(hide: value),
          ),
          _Switch(
            switchKey: const ValueKey('streamer-mode-capture'),
            title: 'Hide this window from screen capture',
            subtitle: controller.canHideFromCapture
                ? 'The recording sees whatever is behind Flucord. Off by '
                      'default: a window that vanished with no explanation '
                      'is its own problem.'
                : 'This platform cannot exclude a window from capture.',
            value: settings.hideFromCapture,
            onChanged: controller.canHideFromCapture
                ? (value) => controller.setHideFromCapture(hide: value)
                : null,
          ),
          if (controller.wasCaptureShieldRefused)
            Padding(
              key: const ValueKey('streamer-mode-capture-refused'),
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                // Said out loud: believing the window is hidden when it is
                // still on the recording is the one failure this must not
                // pass over in silence.
                'Windows would not exclude the window. It is still visible '
                'to a screen recorder.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.switchKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String subtitle;
  final bool value;

  /// Null where the platform cannot honour the switch, which leaves it drawn
  /// and dead rather than hidden — somebody looking for it should find it and
  /// read why.
  final Future<void> Function(bool)? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: switchKey,
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: onChanged == null
        ? null
        : (next) => unawaited(onChanged!(next)),
    title: Text(title, style: const TextStyle(fontSize: 13)),
    subtitle: Text(
      subtitle,
      style: TextStyle(fontSize: 11, color: context.surfaces.muted),
    ),
  );
}
