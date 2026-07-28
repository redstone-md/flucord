import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/slash_command_controller.dart';
import '../../domain/application_command.dart';
import '../../theme/flucord_theme.dart';

/// The command list Discord shows above the composer after a slash.
class SlashCommandList extends StatelessWidget {
  const SlashCommandList({
    required this.controller,
    required this.onPicked,
    super.key,
  });

  final SlashCommandController controller;

  /// Called once a command has been run, so the composer can clear itself.
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) {
    if (!controller.isSupported || !controller.isOpen) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('slash-command-list'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.surfaces.border),
      ),
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (controller.isLoading && controller.commands.isEmpty) {
      return const Padding(
        key: ValueKey('slash-command-loading'),
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (controller.commands.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Text(
          controller.error == null
              ? 'No command matches that.'
              : 'Discord did not return any commands.',
          key: const ValueKey('slash-command-empty'),
          style: TextStyle(color: context.surfaces.muted, fontSize: 12),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: controller.commands.length,
      itemBuilder: (context, index) {
        final command = controller.commands[index];
        return _CommandRow(
          command: command,
          isBusy: controller.isSending,
          onPressed: () => unawaited(_run(context, command)),
        );
      },
    );
  }

  Future<void> _run(BuildContext context, ApplicationCommand command) async {
    var values = const <String, Object?>{};
    if (command.hasRequiredInputs) {
      final filled = await SlashCommandOptionsDialog.show(context, command);
      // Backing out of the form is not running the command with nothing in it.
      if (filled == null) return;
      values = filled;
    }
    if (await controller.invoke(command, values: values)) onPicked();
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.isBusy,
    required this.onPressed,
  });

  final ApplicationCommand command;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('slash-command-${command.id}'),
    onTap: isBusy ? null : onPressed,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            '/${command.name}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (command.description.isNotEmpty) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                command.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.surfaces.muted, fontSize: 12),
              ),
            ),
          ] else
            const Spacer(),
          if (command.hasRequiredInputs)
            Icon(Icons.edit_outlined, size: 13, color: context.surfaces.muted),
        ],
      ),
    ),
  );
}

/// Collects the options a command insists on before it can run.
class SlashCommandOptionsDialog extends StatefulWidget {
  const SlashCommandOptionsDialog({required this.command, super.key});

  final ApplicationCommand command;

  static Future<Map<String, Object?>?> show(
    BuildContext context,
    ApplicationCommand command,
  ) => showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => SlashCommandOptionsDialog(command: command),
  );

  @override
  State<SlashCommandOptionsDialog> createState() =>
      _SlashCommandOptionsDialogState();
}

class _SlashCommandOptionsDialogState extends State<SlashCommandOptionsDialog> {
  final Map<String, TextEditingController> _fields = {};

  @override
  void initState() {
    super.initState();
    for (final option in widget.command.inputs) {
      _fields[option.name] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  bool get _isComplete => widget.command.inputs
      .where((option) => option.isRequired)
      .every((option) => _fields[option.name]!.text.trim().isNotEmpty);

  void _submit() {
    if (!_isComplete) return;
    Navigator.of(context).pop({
      for (final option in widget.command.inputs)
        if (_fields[option.name]!.text.trim().isNotEmpty)
          // Everything is collected as text; Discord types the value from the
          // option's own declaration, and a number typed into a string option
          // is still a string to it.
          option.name: _fields[option.name]!.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('slash-command-options'),
    title: Text('/${widget.command.name}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in widget.command.inputs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: ValueKey('slash-option-${option.name}'),
                controller: _fields[option.name],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: option.isRequired
                      ? '${option.name} *'
                      : option.name,
                  helperText: option.description.isEmpty
                      ? null
                      : option.description,
                  isDense: true,
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('slash-options-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('slash-options-run'),
        onPressed: _isComplete ? _submit : null,
        child: const Text('Run'),
      ),
    ],
  );
}
