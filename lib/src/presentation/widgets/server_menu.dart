import 'package:flutter/material.dart';

/// What can be done to a server, from its header in the sidebar and from its
/// button on the rail.
enum ServerMenuAction { markRead, settings, notifications, report, leave }

/// The rows of a server menu. Only the given [actions] show, in a fixed order.
List<PopupMenuEntry<ServerMenuAction>> serverMenuItems(
  Set<ServerMenuAction> actions,
) => [
  for (final (action, key, label) in const [
    (ServerMenuAction.markRead, 'server-menu-mark-read', 'Mark as read'),
    (ServerMenuAction.settings, 'open-server-settings', 'Server settings'),
    (
      ServerMenuAction.notifications,
      'space-notification-menu',
      'Notification settings',
    ),
    (ServerMenuAction.report, 'report-server', 'Report server'),
    (ServerMenuAction.leave, 'leave-server', 'Leave server'),
  ])
    if (actions.contains(action))
      PopupMenuItem(
        key: ValueKey(key),
        value: action,
        height: 36,
        child: Text(label),
      ),
];
