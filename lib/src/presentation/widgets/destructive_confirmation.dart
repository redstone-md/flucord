import 'package:flutter/material.dart';
import 'flucord_dialog.dart';
import '../../theme/flucord_theme.dart';

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
      return FlucordDialog(
        key: dialogKey,
        title: Text(title),
        // A message can quote somebody's text, so a long one is cut short.
        content: Text(message, maxLines: 5, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          DangerButton(
            key: confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: confirmLabel,
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// The button that does something that cannot be undone, in the theme's
/// danger colour. Every dialog that ends in such an action uses it.
class DangerButton extends StatelessWidget {
  const DangerButton({required this.onPressed, required this.label, super.key});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: context.surfaces.danger,
        foregroundColor: Theme.of(context).colorScheme.onError,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
