import 'package:flutter/material.dart';

import 'flucord_button.dart';
import 'flucord_dialog.dart';

/// The key of the confirm button when a caller does not name its own.
const destructiveConfirmKey = ValueKey('destructive-confirm');

/// Asks before an action that cannot be undone from here.
///
/// The one confirm dialog in the app, so every destructive action looks and
/// answers the same way. [confirmLabel] names the action, on the only button
/// in the danger colour. [detail] shows what is lost, such as the server
/// being left. Answers true only for that button or Enter: Cancel, Escape
/// and a tap outside all answer false.
Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  Widget? detail,
  Key? dialogKey,
  Key confirmKey = destructiveConfirmKey,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      void answer(bool value) => Navigator.of(dialogContext).pop(value);
      return FlucordDialog(
        key: dialogKey,
        maxWidth: 400,
        title: Text(title),
        description: message,
        content: detail,
        confirm: FlucordDialogConfirm(
          key: confirmKey,
          label: confirmLabel,
          kind: FlucordButtonKind.danger,
          onPressed: () => answer(true),
        ),
      );
    },
  );
  return confirmed ?? false;
}
