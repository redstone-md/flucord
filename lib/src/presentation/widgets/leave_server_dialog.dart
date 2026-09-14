import 'package:flutter/material.dart';

/// Asks before leaving a server.
///
/// Leaving is not undoable from any surface Flucord has, so the ask names
/// the server and what disappears with it. Answers whether the user
/// confirmed.
Future<bool> showLeaveServerConfirmation(
  BuildContext context, {
  required String serverName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('leave-server-dialog'),
      title: Text('Leave $serverName?'),
      content: const Text(
        'You will not see this server or its messages until you are invited '
        'back.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('leave-server-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Leave'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
