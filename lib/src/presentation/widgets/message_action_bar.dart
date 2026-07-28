import 'package:flutter/material.dart';

import '../../domain/automod_rule.dart';
import '../../domain/channel_capabilities.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'emoji_picker.dart';

/// The hover toolbar over a message.
///
/// Every control here is offered only when the channel's permissions allow the
/// action behind it. Discord withholds the affordance rather than the request:
/// a pin button that always appears and then fails is indistinguishable, to the
/// person clicking it, from a broken client.
class MessageActionBar extends StatelessWidget {
  const MessageActionBar({
    required this.message,
    required this.workspace,
    required this.capabilities,
    required this.isCurrentUser,
    required this.onReply,
    required this.onAddReaction,
    required this.onReactionPickerToggled,
    required this.onShowReactionDetails,
    required this.onCreateThread,
    required this.onForward,
    required this.onToggleSuppressEmbeds,
    required this.onEdit,
    required this.onTogglePin,
    required this.onDelete,
    this.onResolveAlert,
    this.onReport,
    this.apps,
    super.key,
  });

  final ChatMessage message;
  final ChatWorkspace workspace;
  final ChannelCapabilities capabilities;
  final bool isCurrentUser;
  final VoidCallback onReply;
  final ValueChanged<String> onAddReaction;
  final ValueChanged<bool> onReactionPickerToggled;
  final ValueChanged<MessageReaction> onShowReactionDetails;
  final VoidCallback onCreateThread;
  final VoidCallback onForward;
  final VoidCallback onToggleSuppressEmbeds;
  final VoidCallback onEdit;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  /// Acts on an AutoMod alert. Null on a transport that cannot, in which case
  /// the alert controls are not offered at all.
  final ValueChanged<AutoModAlertAction>? onResolveAlert;

  /// Reports the message to Discord. Null on a transport with no report flow.
  final VoidCallback? onReport;

  /// The Apps entry, or null where context-menu commands cannot run.
  final Widget? apps;

  @override
  Widget build(BuildContext context) {
    final canModerate = capabilities.canModerate(
      message,
      currentMemberId: workspace.currentMemberId,
    );
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border.all(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?apps,
          if (capabilities.sendMessages)
            _ActionButton(
              icon: Icons.reply,
              tooltip: 'Reply',
              onPressed: onReply,
            ),
          if (capabilities.addReactions) _reactionPicker(),
          if (message.reactions.isNotEmpty)
            _ActionButton(
              buttonKey: ValueKey('view-reactions-${message.id}'),
              icon: Icons.people_alt_outlined,
              tooltip: 'View reactions',
              onPressed: () => onShowReactionDetails(message.reactions.first),
            ),
          if (capabilities.createPublicThreads)
            _ActionButton(
              buttonKey: ValueKey('create-thread-${message.id}'),
              icon: Icons.forum_outlined,
              tooltip: 'Create thread',
              onPressed: onCreateThread,
            ),
          if (message.canForward)
            _ActionButton(
              buttonKey: ValueKey('forward-message-${message.id}'),
              icon: Icons.forward_outlined,
              tooltip: 'Forward',
              onPressed: onForward,
            ),
          if ((message.embeds.isNotEmpty || message.suppressesEmbeds) &&
              canModerate)
            _ActionButton(
              buttonKey: ValueKey('suppress-embeds-${message.id}'),
              icon: message.suppressesEmbeds
                  ? Icons.link_outlined
                  : Icons.link_off_outlined,
              tooltip: message.suppressesEmbeds
                  ? 'Show embeds'
                  : 'Suppress embeds',
              onPressed: onToggleSuppressEmbeds,
            ),
          if (isCurrentUser && message.canEdit)
            _ActionButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit',
              onPressed: onEdit,
            ),
          // Only on the alert AutoMod posted, and only for somebody who may
          // moderate the alert channel — which is the same check Discord makes
          // before offering these at all.
          if (message.type == DiscordMessageType.autoModerationAction &&
              capabilities.manageMessages &&
              onResolveAlert != null) ...[
            _ActionButton(
              buttonKey: ValueKey('automod-alert-complete-${message.id}'),
              icon: Icons.task_alt,
              tooltip: 'Mark handled',
              onPressed: () => onResolveAlert!(AutoModAlertAction.setCompleted),
            ),
            _ActionButton(
              buttonKey: ValueKey('automod-alert-reopen-${message.id}'),
              icon: Icons.restart_alt,
              tooltip: 'Reopen',
              onPressed: () =>
                  onResolveAlert!(AutoModAlertAction.unsetCompleted),
            ),
            _ActionButton(
              buttonKey: ValueKey('automod-alert-delete-${message.id}'),
              icon: Icons.delete_sweep_outlined,
              // Deletes what tripped the rule, not the alert. Spelled out
              // because the delete button beside it does the opposite.
              tooltip: 'Delete the flagged message',
              onPressed: () =>
                  onResolveAlert!(AutoModAlertAction.deleteUserMessage),
            ),
            _ActionButton(
              buttonKey: ValueKey('automod-alert-feedback-${message.id}'),
              icon: Icons.thumb_down_alt_outlined,
              tooltip: 'Report as wrong',
              onPressed: () =>
                  onResolveAlert!(AutoModAlertAction.submitFeedback),
            ),
          ],
          // Reporting somebody's own message would be reporting oneself, and
          // Discord withholds it there for the same reason.
          if (onReport != null && !isCurrentUser)
            _ActionButton(
              buttonKey: ValueKey('report-message-${message.id}'),
              icon: Icons.flag_outlined,
              tooltip: 'Report message',
              onPressed: onReport!,
            ),
          if (capabilities.pinMessages)
            _ActionButton(
              icon: message.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              tooltip: message.isPinned ? 'Unpin' : 'Pin',
              onPressed: onTogglePin,
            ),
          if (canModerate)
            _ActionButton(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              destructive: true,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  Widget _reactionPicker() {
    final channel = workspace.channelById(message.channelId);
    final space = workspace.spaceById(channel.spaceId);
    return EmojiPickerButton(
      buttonKey: ValueKey('add-reaction-${message.id}'),
      spaceName: space.name,
      customEmojis: workspace.emojisFor(space.id),
      purpose: EmojiPickerPurpose.reaction,
      dimension: 30,
      iconSize: 16,
      onMenuStateChanged: onReactionPickerToggled,
      onSelected: onAddReaction,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
    this.destructive = false,
  });

  final Key? buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
    onPressed: onPressed,
    icon: Icon(
      icon,
      size: 16,
      color: destructive ? Theme.of(context).colorScheme.error : null,
    ),
    tooltip: tooltip,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
  );
}
