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
              // A call start is marked green, as Discord marks it.
              child: FlucordIcon(
                descriptor.icon,
                size: 16,
                color: message.type == DiscordMessageType.call
                    ? context.surfaces.success
                    : null,
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

final class _SystemMessageDescriptor {
  const _SystemMessageDescriptor({required this.icon, required this.text});

  final FlucordIconData icon;
  final String text;

  factory _SystemMessageDescriptor.from(ChatMessage message, String author) {
    final icon = switch (message.type) {
      DiscordMessageType.recipientAdd => FlucordIcons.invite,
      DiscordMessageType.recipientRemove => FlucordIcons.removeFriend,
      DiscordMessageType.call => FlucordIcons.call,
      DiscordMessageType.channelNameChange => FlucordIcons.edit,
      DiscordMessageType.channelIconChange => FlucordIcons.image,
      DiscordMessageType.channelPinnedMessage => FlucordIcons.pin,
      DiscordMessageType.userJoin => FlucordIcons.joined,
      DiscordMessageType.guildBoost ||
      DiscordMessageType.guildBoostTier1 ||
      DiscordMessageType.guildBoostTier2 ||
      DiscordMessageType.guildBoostTier3 => FlucordIcons.boost,
      DiscordMessageType.channelFollowAdd => FlucordIcons.notifications,
      DiscordMessageType.guildDiscoveryRequalified => FlucordIcons.explore,
      DiscordMessageType.guildDiscoveryDisqualified ||
      DiscordMessageType.guildDiscoveryGracePeriodInitialWarning ||
      DiscordMessageType.guildDiscoveryGracePeriodFinalWarning =>
        FlucordIcons.warning,
      DiscordMessageType.threadCreated => FlucordIcons.threads,
      DiscordMessageType.guildInviteReminder => FlucordIcons.invite,
      DiscordMessageType.roleSubscriptionPurchase ||
      DiscordMessageType.guildApplicationPremiumSubscription =>
        FlucordIcons.entitlements,
      DiscordMessageType.stageStart => FlucordIcons.stage,
      DiscordMessageType.stageEnd => FlucordIcons.stop,
      DiscordMessageType.stageSpeaker => FlucordIcons.mic,
      DiscordMessageType.stageTopic => FlucordIcons.edit,
      DiscordMessageType.guildIncidentAlertModeEnabled =>
        FlucordIcons.alertMode,
      DiscordMessageType.guildIncidentAlertModeDisabled =>
        FlucordIcons.alertModeOff,
      DiscordMessageType.guildIncidentReportRaid => FlucordIcons.report,
      DiscordMessageType.guildIncidentReportFalseAlarm =>
        FlucordIcons.reportOff,
      _ => FlucordIcons.info,
    };
    return _SystemMessageDescriptor(
      icon: icon,
      text: SystemMessageText.describe(message, author),
    );
  }
}
