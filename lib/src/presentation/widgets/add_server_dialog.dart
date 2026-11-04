import 'package:flutter/material.dart';

import '../../application/chat_controller.dart';
import 'create_server_dialog.dart';
import 'flucord_button.dart';
import 'join_server_dialog.dart';
import 'flucord_dialog.dart';

/// Discord's add-a-server entry: two choices, one that joins and one that
/// creates. Each opens its own dialog and hands back the space that was
/// gained, so the caller can land the user inside it.
enum AddServerChoice { join, create }

/// Asks which way the user wants to add a server.
Future<AddServerChoice> showAddServerChoice(BuildContext context) async {
  final choice = await showDialog<AddServerChoice>(
    context: context,
    builder: (dialogContext) => FlucordDialog(
      key: const ValueKey('add-server-dialog'),
      title: const Text('Add a server'),
      description: 'Join a server with an invite, or start your own.',
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
    return FlucordButton(
      key: ValueKey(isJoin ? 'add-server-join' : 'add-server-create'),
      kind: isJoin ? FlucordButtonKind.secondary : FlucordButtonKind.primary,
      label: isJoin ? 'Join a server' : 'Create a server',
      onPressed: () => Navigator.of(context).pop(choice),
    );
  }
}
