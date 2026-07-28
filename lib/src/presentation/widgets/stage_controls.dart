import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/stage_controller.dart';
import '../../domain/stage_channel.dart';
import '../../theme/flucord_theme.dart';

/// The strip a stage channel shows above its participants.
///
/// A stage is not a voice channel with different decoration: everyone who
/// walks in is muted by Discord until a moderator lets them speak, so the room
/// has to offer the one action the audience actually has — asking. Without it a
/// stage looks like a voice channel whose microphone is broken.
class StageControls extends StatelessWidget {
  const StageControls({required this.controller, super.key});

  final StageController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.isSupported || controller.channelId == null) {
      return const SizedBox.shrink();
    }
    final role = controller.role;
    return Container(
      key: const ValueKey('stage-controls'),
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.surfaces.border),
      ),
      child: Row(
        children: [
          Icon(
            controller.isLive ? Icons.campaign : Icons.campaign_outlined,
            size: 17,
            color: controller.isLive
                ? FlucordColors.brand
                : context.surfaces.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  controller.isLive
                      ? (controller.topic.isEmpty
                            ? 'Stage is live'
                            : controller.topic)
                      : 'No stage is running here',
                  key: const ValueKey('stage-topic'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _roleLabel(role),
                  key: const ValueKey('stage-role'),
                  style: TextStyle(color: context.surfaces.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: 'Discord did not accept that.',
                child: Icon(
                  Icons.error_outline,
                  key: const ValueKey('stage-error'),
                  size: 15,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ..._actions(context, role),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, StageRole role) {
    if (!controller.isLive) return const [];
    final busy = controller.isBusy;
    return switch (role) {
      StageRole.audience => [
        FilledButton.tonalIcon(
          key: const ValueKey('stage-request'),
          onPressed: busy ? null : () => unawaited(controller.requestToSpeak()),
          icon: const Icon(Icons.pan_tool_alt_outlined, size: 15),
          label: const Text('Request to speak'),
        ),
      ],
      StageRole.requestedToSpeak => [
        TextButton(
          key: const ValueKey('stage-cancel-request'),
          onPressed: busy ? null : () => unawaited(controller.cancelRequest()),
          child: const Text('Cancel request'),
        ),
      ],
      StageRole.invitedToSpeak => [
        TextButton(
          key: const ValueKey('stage-decline'),
          onPressed: busy ? null : () => unawaited(controller.cancelRequest()),
          child: const Text('Not now'),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          key: const ValueKey('stage-accept'),
          onPressed: busy ? null : () => unawaited(controller.takeStage()),
          icon: const Icon(Icons.mic_none, size: 15),
          label: const Text('Speak'),
        ),
      ],
      StageRole.speaker => [
        TextButton.icon(
          key: const ValueKey('stage-step-down'),
          onPressed: busy ? null : () => unawaited(controller.leaveStage()),
          icon: const Icon(Icons.mic_off_outlined, size: 15),
          label: const Text('Move to audience'),
        ),
      ],
    };
  }

  static String _roleLabel(StageRole role) => switch (role) {
    StageRole.audience => 'You are in the audience.',
    StageRole.requestedToSpeak => 'Your hand is raised.',
    StageRole.invitedToSpeak => 'A moderator invited you to speak.',
    StageRole.speaker => 'You are on stage.',
  };
}
