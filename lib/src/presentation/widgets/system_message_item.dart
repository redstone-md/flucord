import 'package:flutter/material.dart';

import '../../application/system_message_text.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'message_timestamp.dart';

class SystemMessageItem extends StatelessWidget {
  const SystemMessageItem({
    required this.message,
    required this.member,
    required this.workspace,
    required this.onJumpToMessage,
    required this.onSelectChannel,
    super.key,
  });

  final ChatMessage message;
  final Member member;
  final ChatWorkspace workspace;
  final ValueChanged<String> onJumpToMessage;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    final descriptor = _SystemMessageDescriptor.from(
      message,
      member.displayNameFor(
        workspace.channelOrNull(message.channelId)?.spaceId,
      ),
    );
    final action = _action();
    return Semantics(
      label:
          '${descriptor.text}, ${MessageTimestamp.of(context, message.sentAt)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.surfaces.inset,
                border: Border.all(color: context.surfaces.border),
                borderRadius: FlucordRadius.full,
              ),
              child: FlucordIcon(
                descriptor.icon,
                size: 16,
                color: descriptor.tint?.call(context.surfaces),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 2,
                children: [
                  Text(
                    descriptor.text,
                    style: const TextStyle(
                      fontSize: FlucordType.body,
                      height: 1.3,
                    ),
                  ),
                  if (action != null)
                    TextButton(
                      key: ValueKey('system-message-action-${message.id}'),
                      onPressed: action.onPressed,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: FlucordTextRole.caption.strong,
                      ),
                      child: Text(action.label),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MessageTimeLabel(
              message.sentAt,
              style: TextStyle(
                fontSize: FlucordType.caption,
                color: context.surfaces.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  _SystemMessageAction? _action() {
    final reference = message.reference;
    if (message.type == DiscordMessageType.channelPinnedMessage &&
        reference?.messageId != null) {
      return _SystemMessageAction(
        label: 'View message',
        onPressed: () => onJumpToMessage(reference!.messageId!),
      );
    }
    if (message.type == DiscordMessageType.threadCreated &&
        reference?.channelId != null &&
        workspace.channelOrNull(reference!.channelId!) != null) {
      return _SystemMessageAction(
        label: 'Open thread',
        onPressed: () => onSelectChannel(reference.channelId!),
      );
    }
    return null;
  }
}

final class _SystemMessageAction {
  const _SystemMessageAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// The colour an icon takes from the theme.
typedef _Tint = Color Function(FlucordSurfaceTheme surfaces);

final class _SystemMessageDescriptor {
  const _SystemMessageDescriptor({
    required this.icon,
    required this.text,
    this.tint,
  });

  final FlucordIconData icon;

  /// The icon's colour, or null for the text's.
  final _Tint? tint;
  final String text;

  factory _SystemMessageDescriptor.from(ChatMessage message, String author) {
    final (icon, tint) = switch (message.type) {
      DiscordMessageType.recipientAdd => (FlucordIcons.invite, null),
      DiscordMessageType.recipientRemove => (FlucordIcons.removeFriend, null),
      // A call start is marked green, as Discord marks it.
      DiscordMessageType.call => (
        FlucordIcons.call,
        (FlucordSurfaceTheme surfaces) => surfaces.success,
      ),
      DiscordMessageType.channelNameChange => (FlucordIcons.edit, null),
      DiscordMessageType.channelIconChange => (FlucordIcons.image, null),
      DiscordMessageType.channelPinnedMessage => (FlucordIcons.pin, null),
      DiscordMessageType.userJoin => (FlucordIcons.joined, null),
      DiscordMessageType.guildBoost ||
      DiscordMessageType.guildBoostTier1 ||
      DiscordMessageType.guildBoostTier2 ||
      DiscordMessageType.guildBoostTier3 => (FlucordIcons.boost, null),
      DiscordMessageType.channelFollowAdd => (FlucordIcons.notifications, null),
      DiscordMessageType.guildDiscoveryRequalified => (
        FlucordIcons.explore,
        null,
      ),
      DiscordMessageType.guildDiscoveryDisqualified ||
      DiscordMessageType.guildDiscoveryGracePeriodInitialWarning ||
      DiscordMessageType.guildDiscoveryGracePeriodFinalWarning => (
        FlucordIcons.warning,
        null,
      ),
      DiscordMessageType.threadCreated => (FlucordIcons.threads, null),
      DiscordMessageType.guildInviteReminder => (FlucordIcons.invite, null),
      DiscordMessageType.roleSubscriptionPurchase ||
      DiscordMessageType.guildApplicationPremiumSubscription => (
        FlucordIcons.entitlements,
        null,
      ),
      DiscordMessageType.stageStart => (FlucordIcons.stage, null),
      DiscordMessageType.stageEnd => (FlucordIcons.stop, null),
      DiscordMessageType.stageSpeaker => (FlucordIcons.mic, null),
      DiscordMessageType.stageTopic => (FlucordIcons.edit, null),
      DiscordMessageType.guildIncidentAlertModeEnabled => (
        FlucordIcons.alertMode,
        null,
      ),
      DiscordMessageType.guildIncidentAlertModeDisabled => (
        FlucordIcons.alertModeOff,
        null,
      ),
      DiscordMessageType.guildIncidentReportRaid => (FlucordIcons.report, null),
      DiscordMessageType.guildIncidentReportFalseAlarm => (
        FlucordIcons.reportOff,
        null,
      ),
      _ => (FlucordIcons.info, null),
    };
    return _SystemMessageDescriptor(
      icon: icon,
      tint: tint,
      text: SystemMessageText.describe(message, author),
    );
  }
}
