import 'package:flutter/material.dart';

import '../../application/self_presence_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/presence_repository.dart';
import '../../theme/flucord_theme.dart';
import 'presence_indicator.dart';

/// What a status row can ask for beyond picking one of the four statuses.
enum _StatusMenuAction { custom, clearCustom }

/// The account's status picker.
///
/// Only the four statuses Discord lets an account choose are offered.
/// `streaming` is synthesised at render time and `unknown` is what the server
/// writes, so a picker that listed them would be offering to store a value no
/// client can hold.
class SelfStatusMenu extends StatelessWidget {
  const SelfStatusMenu({required this.controller, this.child, super.key});

  final SelfPresenceController controller;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final custom = controller.customStatus;
    return PopupMenuButton<Object>(
      key: const ValueKey('self-status-menu'),
      enabled: controller.canEdit,
      tooltip: controller.canEdit
          ? 'Set your status'
          : 'Status is unavailable for this session',
      position: PopupMenuPosition.over,
      onSelected: (value) => _select(context, value),
      itemBuilder: (context) => [
        for (final status in Presence.selectable)
          PopupMenuItem<Object>(
            key: ValueKey('self-status-${status.name}'),
            value: status,
            child: _StatusRow(
              status: status,
              selected: status == controller.chosenStatus,
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          key: const ValueKey('self-status-custom'),
          value: _StatusMenuAction.custom,
          child: Text(
            custom == null ? 'Set a custom status' : 'Edit custom status',
          ),
        ),
        if (custom != null)
          const PopupMenuItem<Object>(
            key: ValueKey('self-status-clear-custom'),
            value: _StatusMenuAction.clearCustom,
            child: Text('Clear custom status'),
          ),
      ],
      child: child,
    );
  }

  Future<void> _select(BuildContext context, Object value) async {
    if (value is Presence) {
      await controller.setStatus(value);
      return;
    }
    if (value == _StatusMenuAction.clearCustom) {
      await controller.setCustomStatus();
      return;
    }
    final result = await showDialog<CustomStatusDraft>(
      context: context,
      builder: (context) => CustomStatusDialog(
        initialText: controller.customStatus?.state ?? '',
        initialEmoji: controller.customStatus?.emoji?.name ?? '',
      ),
    );
    if (result == null) return;
    await controller.setCustomStatus(
      text: result.text,
      emojiName: result.emojiName,
      expiry: result.expiry,
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status, required this.selected});

  final Presence status;
  final bool selected;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      PresenceIndicator(
        presence: UserPresence(status: status),
        size: 12,
        borderColor: Colors.transparent,
        borderWidth: 0,
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(status.label)),
      if (selected) const Icon(Icons.check, size: 16),
    ],
  );
}

/// What the custom-status dialog hands back.
final class CustomStatusDraft {
  const CustomStatusDraft({
    required this.text,
    required this.emojiName,
    required this.expiry,
  });

  final String text;
  final String emojiName;
  final CustomStatusDuration expiry;
}

/// Discord's "Set a custom status" sheet: a message, an emoji and a timer.
class CustomStatusDialog extends StatefulWidget {
  const CustomStatusDialog({
    this.initialText = '',
    this.initialEmoji = '',
    super.key,
  });

  final String initialText;
  final String initialEmoji;

  @override
  State<CustomStatusDialog> createState() => _CustomStatusDialogState();
}

class _CustomStatusDialogState extends State<CustomStatusDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );
  late final TextEditingController _emoji = TextEditingController(
    text: widget.initialEmoji,
  );
  CustomStatusDuration _expiry = CustomStatusDuration.never;

  @override
  void dispose() {
    _text.dispose();
    _emoji.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('custom-status-dialog'),
    title: const Text('Set a custom status'),
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: TextField(
                  key: const ValueKey('custom-status-emoji'),
                  controller: _emoji,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '🙂',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('custom-status-text'),
                  controller: _text,
                  // R07's write validator caps every status text leaf at 128.
                  maxLength: 128,
                  decoration: InputDecoration(
                    isDense: true,
                    counterStyle: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 9,
                    ),
                    hintText: "What's happening?",
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<CustomStatusDuration>(
            key: const ValueKey('custom-status-expiry'),
            initialValue: _expiry,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Clear after',
            ),
            items: [
              for (final option in CustomStatusDuration.values)
                DropdownMenuItem(value: option, child: Text(option.label)),
            ],
            onChanged: (value) =>
                setState(() => _expiry = value ?? CustomStatusDuration.never),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('custom-status-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('custom-status-save'),
        onPressed: () => Navigator.of(context).pop(
          CustomStatusDraft(
            text: _text.text.trim(),
            emojiName: _emoji.text.trim(),
            expiry: _expiry,
          ),
        ),
        child: const Text('Save'),
      ),
    ],
  );
}
