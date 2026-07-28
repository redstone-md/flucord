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
          if (controller.canModerate) ...[
            const SizedBox(width: 4),
            _ModeratorMenu(controller: controller),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, StageRole role) {
    if (!controller.isLive) {
      // A moderator is offered the one thing that can be done in an empty
      // stage channel; everybody else is simply told nothing is running.
      return controller.canModerate
          ? [
              FilledButton.tonalIcon(
                key: const ValueKey('stage-start'),
                onPressed: controller.isBusy
                    ? null
                    : () => unawaited(_startStage(context)),
                icon: const Icon(Icons.campaign, size: 15),
                label: const Text('Start stage'),
              ),
            ]
          : const [];
    }
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

  /// Asks for a topic, then opens the stage under it.
  ///
  /// Renaming asks the same question but is reached from the moderator menu,
  /// which is only present once a stage is running.
  Future<void> _startStage(BuildContext context) async {
    final topic = await StageTopicDialog.show(
      context,
      initialTopic: '',
      isStarting: true,
    );
    if (topic != null) await controller.startStage(topic);
  }

  static String _roleLabel(StageRole role) => switch (role) {
    StageRole.audience => 'You are in the audience.',
    StageRole.requestedToSpeak => 'Your hand is raised.',
    StageRole.invitedToSpeak => 'A moderator invited you to speak.',
    StageRole.speaker => 'You are on stage.',
  };
}

/// Rename and end, for whoever is running the stage.
class _ModeratorMenu extends StatelessWidget {
  const _ModeratorMenu({required this.controller});

  final StageController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.isLive) return const SizedBox.shrink();
    return PopupMenuButton<_ModeratorAction>(
      key: const ValueKey('stage-moderator-menu'),
      tooltip: 'Manage stage',
      enabled: !controller.isBusy,
      icon: Icon(Icons.more_vert, size: 17, color: context.surfaces.muted),
      onSelected: (action) => unawaited(_run(context, action)),
      itemBuilder: (context) => const [
        PopupMenuItem(
          key: ValueKey('stage-rename'),
          value: _ModeratorAction.rename,
          child: Text('Edit topic'),
        ),
        PopupMenuItem(
          key: ValueKey('stage-end'),
          value: _ModeratorAction.end,
          child: Text('End stage'),
        ),
      ],
    );
  }

  Future<void> _run(BuildContext context, _ModeratorAction action) async {
    switch (action) {
      case _ModeratorAction.rename:
        final topic = await StageTopicDialog.show(
          context,
          initialTopic: controller.topic,
          isStarting: false,
        );
        if (topic != null) await controller.setTopic(topic);
      case _ModeratorAction.end:
        await controller.endStage();
    }
  }
}

enum _ModeratorAction { rename, end }

/// Collects the topic a stage runs under.
class StageTopicDialog extends StatefulWidget {
  const StageTopicDialog({
    required this.initialTopic,
    required this.isStarting,
    super.key,
  });

  final String initialTopic;
  final bool isStarting;

  /// Returns the topic, or null when the user backed out.
  static Future<String?> show(
    BuildContext context, {
    required String initialTopic,
    required bool isStarting,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        StageTopicDialog(initialTopic: initialTopic, isStarting: isStarting),
  );

  @override
  State<StageTopicDialog> createState() => _StageTopicDialogState();
}

class _StageTopicDialogState extends State<StageTopicDialog> {
  late final TextEditingController _topic = TextEditingController(
    text: widget.initialTopic,
  );

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('stage-topic-dialog'),
    title: Text(widget.isStarting ? 'Start a stage' : 'Edit the topic'),
    content: TextField(
      key: const ValueKey('stage-topic-field'),
      controller: _topic,
      autofocus: true,
      maxLength: 120,
      decoration: const InputDecoration(
        labelText: 'Topic',
        helperText: 'What this stage is about.',
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        key: const ValueKey('stage-topic-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      ListenableBuilder(
        listenable: _topic,
        builder: (context, _) => FilledButton(
          key: const ValueKey('stage-topic-confirm'),
          // Discord requires a topic; an empty one comes back as a 400 with
          // nothing on screen to explain it.
          onPressed: _topic.text.trim().isEmpty ? null : _submit,
          child: Text(widget.isStarting ? 'Start' : 'Save'),
        ),
      ),
    ],
  );

  void _submit() {
    final topic = _topic.text.trim();
    if (topic.isEmpty) return;
    Navigator.of(context).pop(topic);
  }
}
