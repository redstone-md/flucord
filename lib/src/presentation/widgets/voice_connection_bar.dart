import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/self_video_controller.dart';

import '../../application/voice_controller.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_theme.dart';
import 'voice_control.dart';
import 'voice_room_status.dart';

/// The strip that says you are still in a voice channel.
///
/// A voice connection outlives the screen that opened it — Discord lets you
/// read another channel while staying in the room — so mute and hang-up cannot
/// live only inside the room view. Without this, walking away from the voice
/// channel left the connection running with no way to leave it, which is the
/// single thing a user reaches for most.
///
/// It listens for itself, so it redraws when voice or the camera changes,
/// even inside a sidebar that is kept across rebuilds.
class VoiceConnectionBar extends StatelessWidget {
  const VoiceConnectionBar({
    required this.controller,
    required this.channelNameFor,
    this.serverNameFor,
    this.onOpenChannel,
    this.camera,
    super.key,
  });

  final VoiceController controller;

  /// Resolves the connected channel's display name, or null when the workspace
  /// does not know the channel.
  final String? Function(String channelId) channelNameFor;

  /// Resolves the name of the server the channel is in. Null for a call, which
  /// has no server.
  final String? Function(String channelId)? serverNameFor;

  /// Returns to the connected room. Null when it cannot be navigated to.
  final void Function(String channelId)? onOpenChannel;

  /// The account's own camera, when this build can send one.
  final SelfVideoController? camera;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, camera]),
    builder: (context, _) => _buildBar(context),
  );

  Widget _buildBar(BuildContext context) {
    final channelId = controller.connectedChannelId;
    if (channelId == null) return const SizedBox.shrink();
    final name = channelNameFor(channelId);
    final server = serverNameFor?.call(channelId);
    final ready = controller.connectionStatus == VoiceConnectionStatus.ready;
    final failed =
        controller.connectionStatus == VoiceConnectionStatus.failure ||
        controller.joinBlockedReason != null;
    final accent = failed
        ? Theme.of(context).colorScheme.error
        : ready
        ? context.surfaces.success
        : context.surfaces.muted;
    return Container(
      key: const ValueKey('voice-connection-bar'),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        border: Border(top: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                failed ? Icons.error_outline : Icons.podcasts,
                size: 15,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      voiceRoomStatusLabel(controller),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      switch ((name, server)) {
                        (final name?, final server?) => '$name / $server',
                        (final name?, null) => name,
                        (null, _) => 'Voice channel',
                      },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (onOpenChannel != null && name != null)
                _BarButton(
                  buttonKey: const ValueKey('voice-bar-open'),
                  tooltip: 'Back to $name',
                  icon: Icons.open_in_full,
                  onPressed: () => onOpenChannel!(channelId),
                ),
              _BarButton(
                buttonKey: const ValueKey('voice-bar-disconnect'),
                tooltip: 'Disconnect',
                icon: Icons.call_end,
                danger: true,
                onPressed: () => unawaited(controller.disconnect()),
              ),
            ],
          ),
          // A row of their own: the sidebar is too narrow to draw these beside
          // the names and still leave the names readable.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BarButton.control(
                buttonKey: const ValueKey('voice-bar-mute'),
                control: VoiceControl.mute(controller),
              ),
              _BarButton.control(
                buttonKey: const ValueKey('voice-bar-deafen'),
                control: VoiceControl.deafen(controller),
              ),
              if (camera case final camera? when camera.isSupported)
                _BarButton.control(
                  buttonKey: const ValueKey('voice-bar-camera'),
                  control: VoiceControl.camera(camera),
                ),
            ],
          ),
          if (voiceRoomWarning(controller) case final warning?)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: Text(
                warning,
                key: const ValueKey('voice-bar-warning'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });

  _BarButton.control({required Key buttonKey, required VoiceControl control})
    : this(
        buttonKey: buttonKey,
        tooltip: control.tooltip,
        icon: control.icon,
        onPressed: control.onPressed,
        active: control.active,
        danger: control.danger,
      );

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    // The disabled shade matches the icon button theme's disabled colour.
    final colour = onPressed == null
        ? context.surfaces.muted.withValues(alpha: 0.38)
        : danger
        ? Theme.of(context).colorScheme.error
        : active
        ? Theme.of(context).colorScheme.onSurface
        : context.surfaces.muted;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: buttonKey,
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(child: Icon(icon, size: 16, color: colour)),
        ),
      ),
    );
  }
}
