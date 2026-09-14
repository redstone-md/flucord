import 'package:flutter/material.dart';

import '../../application/chat_controller.dart';
import '../../theme/flucord_theme.dart';
import 'create_server_dialog.dart';
import 'join_server_dialog.dart';

/// Discord's add-a-server entry: two choices, one that joins and one that
/// creates. Each opens its own dialog and hands back the space that was
/// gained, so the caller can land the user inside it.
enum AddServerChoice { join, create }

/// Asks which way the user wants to add a server.
Future<AddServerChoice> showAddServerChoice(BuildContext context) async {
  final choice = await showDialog<AddServerChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('add-server-dialog'),
      title: const Text('Add a server'),
      content: const SizedBox.shrink(),
      actions: const [
        _ChoiceButton(choice: AddServerChoice.join),
        _ChoiceButton(choice: AddServerChoice.create),
      ],
    ),
  );
  return choice ?? AddServerChoice.join;
}

/// Runs the whole add-server flow: the choice, then the chosen dialog.
/// Answers the gained space's id, or null when the user backed out.
Future<String?> showAddServerFlow(
  BuildContext context, {
  required ChatController chat,
}) async {
  final choice = await showAddServerChoice(context);
  if (!context.mounted) return null;
  return switch (choice) {
    AddServerChoice.join => showJoinServerDialog(context, chat: chat),
    AddServerChoice.create => showCreateServerDialog(context, chat: chat),
  };
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({required this.choice});

  final AddServerChoice choice;

  @override
  Widget build(BuildContext context) {
    final isJoin = choice == AddServerChoice.join;
    return FilledButton.tonalIcon(
      key: ValueKey(isJoin ? 'add-server-join' : 'add-server-create'),
      onPressed: () => Navigator.of(context).pop(choice),
      icon: Icon(isJoin ? Icons.input : Icons.add_circle_outline, size: 18),
      label: Text(isJoin ? 'Join a server' : 'Create a server'),
      style: FilledButton.styleFrom(
        backgroundColor: context.surfaces.raised,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
