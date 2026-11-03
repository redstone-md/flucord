import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/self_video_controller.dart';
import '../../application/voice_controller.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'go_live_button.dart';
import 'go_live_display_dialog.dart';
import 'go_live_scope.dart';
import 'panel_icon_button.dart';
import 'voice_control.dart';
import 'voice_room_status.dart';

/// The voice panel: the strip that says you are still in a voice channel.
///
/// A voice connection outlives the screen that opened it (Discord lets you
/// read another channel while staying in the room), so hang-up cannot live
/// only inside the room view. Without this, walking away from the voice
/// channel left the connection running with no way to leave it, which is the
/// single thing a user reaches for most. Mute and deafen sit in the user
/// panel below, where they stay whether or not a room is open.
///
/// It listens for itself, so it redraws when voice, the camera or a share
/// changes, even inside a sidebar that is kept across rebuilds.
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

  static const _buttonSize = 32.0;
  static const _gap = 8.0;
  static const _hangUpFillAlpha = 0.12;
  static const _controlFillAlpha = 0.05;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, camera]),
    builder: (context, _) => _buildBar(context),
  );

  Widget _buildBar(BuildContext context) {
    final channelId = controller.connectedChannelId;
    if (channelId == null) return const SizedBox.shrink();
    final surfaces = context.surfaces;
    final failed =
        controller.connectionStatus == VoiceConnectionStatus.failure ||
        controller.joinBlockedReason != null;
    final accent = failed
        ? surfaces.danger
        : controller.connectionStatus == VoiceConnectionStatus.ready
        ? surfaces.success
        : surfaces.muted;
    final controlFill = surfaces.text.withValues(alpha: _controlFillAlpha);
    return Container(
      key: const ValueKey('voice-connection-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: _gap),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: surfaces.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _status(context, channelId, accent)),
              const SizedBox(width: _gap),
              PanelIconButton(
                buttonKey: const ValueKey('voice-bar-disconnect'),
                tooltip: 'Disconnect',
                icon: FlucordIcons.hangUp,
                danger: true,
                size: _buttonSize,
                fill: surfaces.danger.withValues(alpha: _hangUpFillAlpha),
                onPressed: () => unawaited(controller.disconnect()),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          Row(
            spacing: _gap,
            children: [
              if (camera case final camera? when camera.isSupported)
                Expanded(
                  child: PanelIconButton.control(
                    buttonKey: const ValueKey('voice-bar-camera'),
                    control: VoiceControl.camera(camera),
                    size: _buttonSize,
                    fill: controlFill,
                  ),
                ),
              Expanded(
                child: PanelIconButton.control(
                  buttonKey: const ValueKey('voice-bar-share'),
                  control: _screenShare(context, channelId),
                  size: _buttonSize,
                  fill: controlFill,
                ),
              ),
              Expanded(
                child: PanelIconButton.control(
                  buttonKey: const ValueKey('voice-bar-activities'),
                  control: const VoiceControl.activities(),
                  size: _buttonSize,
                  fill: controlFill,
                ),
              ),
            ],
          ),
          if (voiceRoomWarning(controller) case final warning?)
            Padding(
              padding: const EdgeInsets.only(top: _gap),
              child: Text(
                warning,
                key: const ValueKey('voice-bar-warning'),
                style: FlucordTextRole.caption.style.copyWith(
                  color: surfaces.errorText,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// "Voice connected" with the signal mark, and the room and server under
  /// it. The room's name leads back to the room.
  Widget _status(BuildContext context, String channelId, Color accent) {
    final name = channelNameFor(channelId);
    final server = serverNameFor?.call(channelId);
    final room = Text(
      switch ((name, server)) {
        (final name?, final server?) => '$name / $server',
        (final name?, null) => name,
        (null, _) => 'Voice channel',
      },
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: FlucordTextRole.caption.style.copyWith(
        color: context.surfaces.captionText,
      ),
    );
    final open = onOpenChannel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          spacing: 4,
          children: [
            FlucordIcon(FlucordIcons.signal, size: 16, color: accent),
            Flexible(
              child: Text(
                voiceRoomStatusLabel(controller),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.label.style.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        if (open != null && name != null)
          Tooltip(
            message: 'Back to $name',
            child: InkWell(
              key: const ValueKey('voice-bar-open'),
              borderRadius: FlucordRadius.small,
              onTap: () => open(channelId),
              child: room,
            ),
          )
        else
          room,
      ],
    );
  }

  /// Go Live from the panel, the same share the room's own button starts.
  VoiceControl _screenShare(BuildContext context, String channelId) =>
      VoiceControl.screenShare(
        GoLiveScope.maybeOf(context),
        toggle: (goLive) => unawaited(
          GoLiveButton.toggle(
            goLive,
            channelId: channelId,
            guildId: controller.connectedGuildId,
            pickSource: () =>
                GoLiveDisplayDialog.pick(context, goLive.displays),
          ),
        ),
      );
}
