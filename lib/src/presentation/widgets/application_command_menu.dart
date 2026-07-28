import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/slash_command_controller.dart';
import '../../domain/application_command.dart';
import '../../theme/flucord_theme.dart';

/// The "Apps" entry Discord puts on a message and on a member.
///
/// Context-menu commands take no options: what they act on *is* the argument,
/// which is why the target travels with the invocation instead of a form.
class ApplicationCommandMenuButton extends StatelessWidget {
  const ApplicationCommandMenuButton({
    required this.controller,
    required this.type,
    required this.targetId,
    this.tooltip = 'Apps',
    super.key,
  });

  final SlashCommandController controller;

  /// Which kind of context-menu command this surface offers.
  final ApplicationCommandType type;

  /// The message or user the command will act on.
  final String targetId;

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    if (!controller.isSupported) return const SizedBox.shrink();
    return IconButton(
      key: ValueKey('apps-menu-$targetId'),
      tooltip: tooltip,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      onPressed: () => unawaited(_open(context)),
      icon: const Icon(Icons.apps),
    );
  }

  Future<void> _open(BuildContext context) async {
    final commands = await controller.contextCommands(type);
    if (!context.mounted) return;
    final chosen = await ApplicationCommandSheet.show(
      context,
      commands: commands,
    );
    if (chosen == null) return;
    await controller.invoke(chosen, targetId: targetId);
  }
}

/// The list of context-menu commands to choose from.
class ApplicationCommandSheet extends StatelessWidget {
  const ApplicationCommandSheet({required this.commands, super.key});

  final List<ApplicationCommand> commands;

  /// Returns the chosen command, or null when nothing was picked.
  static Future<ApplicationCommand?> show(
    BuildContext context, {
    required List<ApplicationCommand> commands,
  }) => showModalBottomSheet<ApplicationCommand>(
    context: context,
    backgroundColor: context.surfaces.canvas,
    builder: (_) => ApplicationCommandSheet(commands: commands),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    key: const ValueKey('apps-sheet'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Apps',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (commands.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No app offers anything here.',
                key: const ValueKey('apps-empty'),
                style: TextStyle(color: context.surfaces.muted, fontSize: 12),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final command in commands)
                    ListTile(
                      key: ValueKey('apps-command-${command.id}'),
                      dense: true,
                      title: Text(command.name),
                      subtitle: command.description.isEmpty
                          ? null
                          : Text(command.description),
                      onTap: () => Navigator.of(context).pop(command),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
