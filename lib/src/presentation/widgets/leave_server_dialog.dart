import 'package:flutter/material.dart';

import 'destructive_confirmation.dart';

/// Asks before leaving a server.
///
/// Leaving is not undoable from any surface Flucord has, so the ask names
/// the server and what disappears with it. Answers whether the user
/// confirmed.
Future<bool> showLeaveServerConfirmation(
  BuildContext context, {
  required String serverName,
}) => confirmDestructiveAction(
  context,
  title: 'Leave $serverName?',
  message:
      'You will not see this server or its messages until you are invited '
      'back.',
  confirmLabel: 'Leave',
  dialogKey: const ValueKey('leave-server-dialog'),
  confirmKey: const ValueKey('leave-server-confirm'),
);
