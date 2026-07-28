import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/message_component_controller.dart';
import '../../domain/message_component.dart';
import 'component_directory_picker.dart';
import '../../theme/flucord_theme.dart';

/// The buttons and selects an application hung off a message.
class MessageComponentRows extends StatelessWidget {
  const MessageComponentRows({
    required this.controller,
    required this.rows,
    required this.messageId,
    required this.applicationId,
    required this.messageFlags,
    required this.onOpenLink,
    this.directoryEntries,
    super.key,
  });

  final MessageComponentController controller;
  final List<MessageActionRow> rows;
  final String messageId;

  /// Whose components these are. Empty when the message names no application,
  /// in which case there is nobody to send an interaction to.
  final String applicationId;

  final int messageFlags;
  final ValueChanged<String> onOpenLink;

  /// What a user, role, channel or mentionable select may resolve to. Null
  /// where the surface has no directory to offer, in which case those selects
  /// stay disabled rather than opening an empty picker.
  final List<DirectoryEntry> Function(MessageComponent component)?
  directoryEntries;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty || !controller.isSupported) {
      return const SizedBox.shrink();
    }
    final busy = controller.isBusy(messageId);
    return Padding(
      key: ValueKey('message-components-$messageId'),
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final component in row.components)
                    _component(context, component, busy: busy),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _component(
    BuildContext context,
    MessageComponent component, {
    required bool busy,
  }) {
    if (component.isSelect) {
      return _SelectMenu(
        component: component,
        isBusy: busy,
        directory: component.type == 3 ? null : directoryEntries,
        onChanged: (values) => unawaited(
          controller.activate(
            messageId: messageId,
            applicationId: applicationId,
            component: component,
            messageFlags: messageFlags,
            values: values,
          ),
        ),
      );
    }
    return _Button(
      component: component,
      isBusy: busy,
      onPressed: () {
        // A link button never reaches Discord: it opens where it points.
        if (component.isLink) {
          if (component.url case final url?) onOpenLink(url);
          return;
        }
        unawaited(
          controller.activate(
            messageId: messageId,
            applicationId: applicationId,
            component: component,
            messageFlags: messageFlags,
          ),
        );
      },
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.component,
    required this.isBusy,
    required this.onPressed,
  });

  final MessageComponent component;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = component.label.isEmpty
        ? (component.emojiName ?? 'Button')
        : component.label;
    final enabled = component.isActionable && !isBusy;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (component.emojiName case final emoji?
            when component.label.isNotEmpty) ...[
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
        ],
        Text(label),
        if (component.isLink) ...[
          const SizedBox(width: 4),
          const Icon(Icons.open_in_new, size: 12),
        ],
      ],
    );
    final key = ValueKey('component-${component.customId}-${component.label}');
    return switch (component.style) {
      MessageButtonStyle.primary => FilledButton(
        key: key,
        onPressed: enabled ? onPressed : null,
        child: child,
      ),
      MessageButtonStyle.success => FilledButton(
        key: key,
        style: FilledButton.styleFrom(backgroundColor: FlucordColors.success),
        onPressed: enabled ? onPressed : null,
        child: child,
      ),
      MessageButtonStyle.danger => FilledButton(
        key: key,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: enabled ? onPressed : null,
        child: child,
      ),
      _ => OutlinedButton(
        key: key,
        onPressed: enabled ? onPressed : null,
        child: child,
      ),
    };
  }
}

class _SelectMenu extends StatelessWidget {
  const _SelectMenu({
    required this.component,
    required this.isBusy,
    required this.directory,
    required this.onChanged,
  });

  final MessageComponent component;
  final bool isBusy;

  /// Supplies the workspace's own entries for a directory select.
  final List<DirectoryEntry> Function(MessageComponent component)? directory;

  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    // Only a string select carries its own choices. The user, role, channel
    // and mentionable flavours name a kind and expect the client to offer the
    // server's own directory, which is what the picker does.
    if (component.type != 3) {
      final entries = directory?.call(component) ?? const <DirectoryEntry>[];
      return OutlinedButton(
        key: ValueKey('component-select-${component.customId}'),
        onPressed: entries.isEmpty || component.isDisabled || isBusy
            ? null
            : () => unawaited(_pick(context, entries)),
        child: Text(
          component.placeholder.isEmpty
              ? 'Make a selection'
              : component.placeholder,
        ),
      );
    }
    if (component.options.isEmpty) {
      return OutlinedButton(
        key: ValueKey('component-select-${component.customId}'),
        onPressed: null,
        child: Text(
          component.placeholder.isEmpty
              ? 'Unsupported menu'
              : component.placeholder,
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DropdownButtonFormField<String>(
        key: ValueKey('component-select-${component.customId}'),
        isExpanded: true,
        initialValue: component.options
            .where((option) => option.isDefault)
            .map((option) => option.value)
            .firstOrNull,
        decoration: InputDecoration(
          isDense: true,
          hintText: component.placeholder.isEmpty
              ? 'Make a selection'
              : component.placeholder,
        ),
        items: [
          for (final option in component.options)
            DropdownMenuItem(
              key: ValueKey('component-option-${option.value}'),
              value: option.value,
              child: Text(option.displayLabel, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: component.isDisabled || isBusy
            ? null
            : (value) {
                if (value != null) onChanged([value]);
              },
      ),
    );
  }

  Future<void> _pick(BuildContext context, List<DirectoryEntry> entries) async {
    final chosen = await ComponentDirectoryPicker.show(
      context,
      title: component.placeholder,
      entries: entries,
      maxValues: component.maxValues,
    );
    if (chosen != null && chosen.isNotEmpty) onChanged(chosen);
  }
}

/// The form an application opens with `INTERACTION_MODAL_CREATE`.
class MessageModalDialog extends StatefulWidget {
  const MessageModalDialog({required this.modal, super.key});

  final ModalDefinition modal;

  /// Returns what was typed, or null when the user closed it.
  static Future<Map<String, String>?> show(
    BuildContext context,
    ModalDefinition modal,
  ) => showDialog<Map<String, String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MessageModalDialog(modal: modal),
  );

  @override
  State<MessageModalDialog> createState() => _MessageModalDialogState();
}

class _MessageModalDialogState extends State<MessageModalDialog> {
  final Map<String, TextEditingController> _fields = {};

  @override
  void initState() {
    super.initState();
    for (final field in widget.modal.fields) {
      // Prefilled by the application, and editable from there.
      _fields[field.customId] = TextEditingController(text: field.value);
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  bool get _isComplete => widget.modal.fields
      .where((field) => field.isRequired)
      .every((field) => _fields[field.customId]!.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('message-modal'),
    title: Text(widget.modal.title.isEmpty ? 'Form' : widget.modal.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final field in widget.modal.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: ValueKey('modal-field-${field.customId}'),
                controller: _fields[field.customId],
                onChanged: (_) => setState(() {}),
                minLines: field.isParagraph ? 3 : 1,
                maxLines: field.isParagraph ? 6 : 1,
                maxLength: field.maxLength > 0 ? field.maxLength : null,
                decoration: InputDecoration(
                  labelText: field.isRequired
                      ? '${field.label} *'
                      : field.label,
                  hintText: field.placeholder.isEmpty
                      ? null
                      : field.placeholder,
                  isDense: true,
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('modal-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('modal-submit'),
        onPressed: _isComplete
            ? () => Navigator.of(context).pop({
                for (final entry in _fields.entries)
                  entry.key: entry.value.text,
              })
            : null,
        child: const Text('Submit'),
      ),
    ],
  );
}
