import 'package:flutter/material.dart';

import '../../application/system_message_text.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

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
    final descriptor = _SystemMessageDescriptor.from(message, member);
    final action = _action();
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(message.sentAt),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );
    return Semantics(
      label: '${descriptor.text}, $time',
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
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(descriptor.icon, size: 16),
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
                    style: const TextStyle(fontSize: 13, height: 1.3),
                  ),
                  if (action != null)
                    TextButton(
                      key: ValueKey('system-message-action-${message.id}'),
                      onPressed: action.onPressed,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(action.label),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: time,
              child: Text(
                time,
                style: TextStyle(fontSize: 10, color: context.surfaces.muted),
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

  final IconData icon;
  final String text;

  factory _SystemMessageDescriptor.from(ChatMessage message, Member member) {
    final icon = switch (message.type) {
      DiscordMessageType.recipientAdd => Icons.person_add_alt_1_outlined,
      DiscordMessageType.recipientRemove => Icons.person_remove_alt_1_outlined,
      DiscordMessageType.call => Icons.call_outlined,
      DiscordMessageType.channelNameChange => Icons.edit_outlined,
      DiscordMessageType.channelIconChange => Icons.image_outlined,
      DiscordMessageType.channelPinnedMessage => Icons.push_pin_outlined,
      DiscordMessageType.userJoin => Icons.login,
      DiscordMessageType.guildBoost => Icons.bolt_outlined,
      DiscordMessageType.guildBoostTier1 ||
      DiscordMessageType.guildBoostTier2 ||
      DiscordMessageType.guildBoostTier3 => Icons.bolt,
      DiscordMessageType.channelFollowAdd =>
        Icons.notifications_active_outlined,
      DiscordMessageType.guildDiscoveryDisqualified =>
        Icons.explore_off_outlined,
      DiscordMessageType.guildDiscoveryRequalified => Icons.explore_outlined,
      DiscordMessageType.guildDiscoveryGracePeriodInitialWarning ||
      DiscordMessageType.guildDiscoveryGracePeriodFinalWarning =>
        Icons.warning_amber,
      DiscordMessageType.threadCreated => Icons.forum_outlined,
      DiscordMessageType.guildInviteReminder => Icons.person_add_alt_outlined,
      DiscordMessageType.roleSubscriptionPurchase ||
      DiscordMessageType.guildApplicationPremiumSubscription =>
        Icons.workspace_premium_outlined,
      DiscordMessageType.stageStart => Icons.podcasts_outlined,
      DiscordMessageType.stageEnd => Icons.stop_circle_outlined,
      DiscordMessageType.stageSpeaker => Icons.mic_outlined,
      DiscordMessageType.stageTopic => Icons.topic_outlined,
      DiscordMessageType.guildIncidentAlertModeEnabled => Icons.shield_outlined,
      DiscordMessageType.guildIncidentAlertModeDisabled =>
        Icons.shield_moon_outlined,
      DiscordMessageType.guildIncidentReportRaid => Icons.report_outlined,
      DiscordMessageType.guildIncidentReportFalseAlarm =>
        Icons.report_off_outlined,
      _ => Icons.info_outline,
    };
    return _SystemMessageDescriptor(
      icon: icon,
      text: SystemMessageText.describe(message, member.displayName),
    );
  }
}
