import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/voice_controller.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_theme.dart';
import 'voice_room_status.dart';

/// The strip that says you are still in a voice channel.
///
/// A voice connection outlives the screen that opened it — Discord lets you
/// read another channel while staying in the room — so mute and hang-up cannot
/// live only inside the room view. Without this, walking away from the voice
/// channel left the connection running with no way to leave it, which is the
/// single thing a user reaches for most.
class VoiceConnectionBar extends StatelessWidget {
  const VoiceConnectionBar({
    required this.controller,
    required this.channelNameFor,
    this.onOpenChannel,
    super.key,
  });

  final VoiceController controller;

  /// Resolves the connected channel's display name, or null when this space
  /// does not know it — the connection may be in another server entirely.
  final String? Function(String channelId) channelNameFor;

  /// Returns to the connected room. Null when it cannot be navigated to.
  final void Function(String channelId)? onOpenChannel;

  @override
  Widget build(BuildContext context) {
    final channelId = controller.connectedChannelId;
    if (channelId == null) return const SizedBox.shrink();
    final name = channelNameFor(channelId);
    final ready = controller.connectionStatus == VoiceConnectionStatus.ready;
    final failed =
        controller.connectionStatus == VoiceConnectionStatus.failure ||
        controller.joinBlockedReason != null;
    final accent = failed
        ? Theme.of(context).colorScheme.error
        : ready
        ? FlucordColors.success
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
                      name ?? 'Voice channel',
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
                buttonKey: const ValueKey('voice-bar-mute'),
                tooltip: controller.isMuted ? 'Unmute' : 'Mute',
                icon: controller.isMuted ? Icons.mic_off : Icons.mic_none,
                active: controller.isMuted,
                onPressed: () => unawaited(controller.toggleMute()),
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

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colour = danger
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
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: colour),
        ),
      ),
    );
  }
}
