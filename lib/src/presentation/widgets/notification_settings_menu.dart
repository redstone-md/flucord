import 'package:flutter/material.dart';

import '../../domain/read_state.dart';

/// What a notification menu row asks the shell to do.
///
/// Modelled as values rather than as one callback per row so the two places
/// that raise this menu — a channel row and the sidebar header — can share
/// every item and let the caller decide what "this scope" means.
sealed class NotificationMenuRequest {
  const NotificationMenuRequest();
}

final class MarkReadRequest extends NotificationMenuRequest {
  const MarkReadRequest();
}

final class MuteRequest extends NotificationMenuRequest {
  const MuteRequest({required this.muted, this.windowSeconds});

  final bool muted;

  /// Seconds until the mute lapses, or `null` for one with no end.
  final int? windowSeconds;
}

final class NotificationLevelRequest extends NotificationMenuRequest {
  const NotificationLevelRequest(this.level);

  final MessageNotificationLevel level;
}

final class SuppressEveryoneRequest extends NotificationMenuRequest {
  const SuppressEveryoneRequest(this.value);

  final bool value;
}

final class MobilePushRequest extends NotificationMenuRequest {
  const MobilePushRequest(this.value);

  final bool value;
}

/// The mute durations Discord's own menu offers, in the order it lists them.
const notificationMuteChoices = <(String, int?)>[
  ('For 15 minutes', 900),
  ('For 1 hour', 3600),
  ('For 3 hours', 10800),
  ('For 8 hours', 28800),
  ('For 24 hours', 86400),
  ('Until I turn it back on', null),
];

/// Builds the rows a notification menu shows.
///
/// [level] is the *resolved* level, so a channel inheriting its guild's
/// setting still shows a tick against what will actually happen. The
/// guild-only rows are dropped for a channel scope, because
/// `suppress_everyone` and `mobile_push` have no per-channel override on the
/// wire and offering them there would write a field the server ignores.
List<PopupMenuEntry<NotificationMenuRequest>> notificationMenuItems({
  required bool muted,
  required MessageNotificationLevel level,
  required bool isSpaceScope,
  bool suppressEveryone = false,
  bool mobilePush = true,
}) => [
  const PopupMenuItem(
    value: MarkReadRequest(),
    height: 36,
    child: Text('Mark as read'),
  ),
  const PopupMenuDivider(),
  if (muted)
    const PopupMenuItem(
      value: MuteRequest(muted: false),
      height: 36,
      child: Text('Unmute'),
    )
  else
    for (final (label, window) in notificationMuteChoices)
      PopupMenuItem(
        value: MuteRequest(muted: true, windowSeconds: window),
        height: 36,
        child: Text('Mute $label'),
      ),
  const PopupMenuDivider(),
  for (final option in const [
    (MessageNotificationLevel.allMessages, 'All messages'),
    (MessageNotificationLevel.onlyMentions, 'Only @mentions'),
    (MessageNotificationLevel.noMessages, 'Nothing'),
  ])
    CheckedPopupMenuItem(
      value: NotificationLevelRequest(option.$1),
      checked: level == option.$1,
      height: 36,
      child: Text(option.$2),
    ),
  if (isSpaceScope) ...[
    const PopupMenuDivider(),
    CheckedPopupMenuItem(
      value: SuppressEveryoneRequest(!suppressEveryone),
      checked: suppressEveryone,
      height: 36,
      child: const Text('Suppress @everyone and @here'),
    ),
    CheckedPopupMenuItem(
      value: MobilePushRequest(!mobilePush),
      checked: mobilePush,
      height: 36,
      child: const Text('Mobile push notifications'),
    ),
  ],
];

/// Raises the notification menu at [position], for a right-clicked row.
Future<NotificationMenuRequest?> showNotificationSettingsMenu({
  required BuildContext context,
  required RelativeRect position,
  required bool muted,
  required MessageNotificationLevel level,
  required bool isSpaceScope,
  bool suppressEveryone = false,
  bool mobilePush = true,
}) => showMenu<NotificationMenuRequest>(
  context: context,
  position: position,
  items: notificationMenuItems(
    muted: muted,
    level: level,
    isSpaceScope: isSpaceScope,
    suppressEveryone: suppressEveryone,
    mobilePush: mobilePush,
  ),
);
