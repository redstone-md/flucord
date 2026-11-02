import 'package:flutter/material.dart';

/// The key of the confirm button when a caller does not name its own.
const destructiveConfirmKey = ValueKey('destructive-confirm');

/// Asks before an action that cannot be undone from here.
///
/// The one confirm dialog in the app, so every destructive action looks and
/// answers the same way. [confirmLabel] names the action, on a button in the
/// theme's danger colour. Answers true only when that button was pressed:
/// Cancel and a tap outside both answer false.
Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  Key? dialogKey,
  Key confirmKey = destructiveConfirmKey,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        key: dialogKey,
        title: Text(title),
        // A message can quote somebody's text, so a long one is cut short.
        content: Text(message, maxLines: 5, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: confirmKey,
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
