import 'package:flutter/material.dart';

import '../../application/keybind_controller.dart';
import '../../domain/keybind.dart';
import '../../theme/flucord_theme.dart';

/// Assigning the keyboard shortcuts.
///
/// Only the actions Flucord can carry out are listed. Discord's own table also
/// has overlay, streamer-mode, clip and screenshot bindings, and offering a
/// row that silently did nothing would be worse than leaving it out.
class KeybindSection extends StatelessWidget {
  const KeybindSection({required this.controller, super.key});

  final KeybindController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      key: const ValueKey('keybind-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Keybinds', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          // Said plainly rather than implied: a binding that looked global and
          // was not would read as broken the first time it was tried behind
          // another window.
          'These work while Flucord has focus. A shortcut that reaches the '
          'client while another window is in front needs a system-wide hook, '
          'which this build does not install.',
          style: TextStyle(fontSize: 12, color: context.surfaces.muted),
        ),
        const SizedBox(height: 12),
        for (final action in KeybindAction.values)
          _KeybindRow(
            action: action,
            binding: controller.bindingFor(action),
            isRecording: controller.recording == action,
            onRecord: () => controller.record(action),
            onCancel: controller.cancelRecording,
            onClear: () => controller.clear(action),
          ),
      ],
    ),
  );
}

class _KeybindRow extends StatelessWidget {
  const _KeybindRow({
    required this.action,
    required this.binding,
    required this.isRecording,
    required this.onRecord,
    required this.onCancel,
    required this.onClear,
  });

  final KeybindAction action;
  final Keybind? binding;
  final bool isRecording;
  final VoidCallback onRecord;
  final VoidCallback onCancel;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(action.label, style: const TextStyle(fontSize: 13)),
              if (action.holdToUse)
                Text(
                  'Held, not toggled',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.surfaces.muted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 150,
          child: FilledButton.tonal(
            key: ValueKey('keybind-record-${action.code}'),
            onPressed: isRecording ? onCancel : onRecord,
            child: Text(
              isRecording
                  ? 'Press any key…'
                  : binding?.label ?? 'Not bound',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(
          key: ValueKey('keybind-clear-${action.code}'),
          tooltip: 'Clear',
          onPressed: binding == null ? null : onClear,
          icon: const Icon(Icons.backspace_outlined, size: 16),
        ),
      ],
    ),
  );
}
