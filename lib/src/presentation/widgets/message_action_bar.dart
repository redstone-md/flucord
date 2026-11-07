import 'package:flutter/material.dart';

import '../../application/expression_favorites_controller.dart';
import '../../domain/automod_rule.dart';
import '../../domain/channel_capabilities.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
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
    this.onAddSuperReaction,
    this.onShowReactionDetails,
    required this.onCreateThread,
    this.onForward,
    this.onToggleSuppressEmbeds,
    required this.onEdit,
    required this.onTogglePin,
    required this.onDelete,
    required this.onMore,
    this.onResolveAlert,
    this.onReport,
    this.expressionFavorites,
    this.apps,
    super.key,
  });

  /// The side of one button.
  static const buttonSize = 28.0;

  static const _inset = 2.0;

  /// The bar's height: one button and the inset around it.
  static const height = buttonSize + 2 * _inset;

  /// The starred expressions, when the transport holds any.
  final ExpressionFavoritesController? expressionFavorites;
  final ChatMessage message;
  final ChatWorkspace workspace;
  final ChannelCapabilities capabilities;
  final bool isCurrentUser;
  final VoidCallback onReply;
  final ValueChanged<String> onAddReaction;
  final ValueChanged<bool> onReactionPickerToggled;

  /// Adds a super reaction, or null where the account cannot send one. Then
  /// there is no button.
  final ValueChanged<String>? onAddSuperReaction;

  /// Opens the list of who reacted, or null where the session cannot list
  /// them. Then there is no button.
  final ValueChanged<MessageReaction>? onShowReactionDetails;
  final VoidCallback onCreateThread;

  /// Null where the session cannot forward, and then there is no button.
  final VoidCallback? onForward;

  /// Null where the session cannot change the flag, and then there is no
  /// button.
  final VoidCallback? onToggleSuppressEmbeds;
  final VoidCallback onEdit;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  /// Opens the message menu, with every action, at this global position.
  final ValueChanged<Offset> onMore;

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
    const corners = FlucordRadius.medium;
    return Container(
      height: height,
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        borderRadius: corners,
      ),
      // In the foreground, so the border takes no height from the buttons.
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: context.surfaces.border),
        borderRadius: corners,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (capabilities.addReactions) ...[
            _reactionPicker(
              buttonKey: ValueKey('add-reaction-${message.id}'),
              purpose: EmojiPickerPurpose.reaction,
              onSelected: onAddReaction,
            ),
            if (onAddSuperReaction case final addSuper?)
              _reactionPicker(
                buttonKey: ValueKey('add-super-reaction-${message.id}'),
                purpose: EmojiPickerPurpose.superReaction,
                onSelected: addSuper,
              ),
          ],
          if (capabilities.sendMessages)
            _ActionButton(
              icon: FlucordIcons.reply,
              tooltip: 'Reply',
              onPressed: onReply,
            ),
          if (capabilities.createPublicThreads)
            _ActionButton(
              buttonKey: ValueKey('create-thread-${message.id}'),
              icon: FlucordIcons.threads,
              tooltip: 'Create thread',
              onPressed: onCreateThread,
            ),
          ?apps,
          if (onShowReactionDetails case final showDetails?
              when message.reactions.isNotEmpty)
            _ActionButton(
              buttonKey: ValueKey('view-reactions-${message.id}'),
              icon: FlucordIcons.members,
              tooltip: 'View reactions',
              onPressed: () => showDetails(message.reactions.first),
            ),
          if (onForward case final forward? when message.canForward)
            _ActionButton(
              buttonKey: ValueKey('forward-message-${message.id}'),
              icon: FlucordIcons.forward,
              tooltip: 'Forward',
              onPressed: forward,
            ),
          if (onToggleSuppressEmbeds case final toggle?
              when (message.embeds.isNotEmpty || message.suppressesEmbeds) &&
                  canModerate)
            _ActionButton(
              buttonKey: ValueKey('suppress-embeds-${message.id}'),
              icon: message.suppressesEmbeds
                  ? FlucordIcons.link
                  : FlucordIcons.unlink,
              tooltip: message.suppressesEmbeds
                  ? 'Show embeds'
                  : 'Suppress embeds',
              onPressed: toggle,
            ),
          if (isCurrentUser && message.canEdit)
            _ActionButton(
              icon: FlucordIcons.edit,
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
              icon: FlucordIcons.done,
              tooltip: 'Mark handled',
              onPressed: () => onResolveAlert!(AutoModAlertAction.setCompleted),
            ),
            _ActionButton(
              buttonKey: ValueKey('automod-alert-reopen-${message.id}'),
              icon: FlucordIcons.reopen,
              tooltip: 'Reopen',
              onPressed: () =>
                  onResolveAlert!(AutoModAlertAction.unsetCompleted),
            ),
            _ActionButton(
              buttonKey: ValueKey('automod-alert-delete-${message.id}'),
              icon: FlucordIcons.deleteFlagged,
              // Deletes what tripped the rule, not the alert. Spelled out
              // because the delete button beside it does the opposite.
              tooltip: 'Delete the flagged message',
              onPressed: () =>
                  onResolveAlert!(AutoModAlertAction.deleteUserMessage),
            ),
            _ActionButton(
              buttonKey: ValueKey('automod-alert-feedback-${message.id}'),
              icon: FlucordIcons.thumbsDown,
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
              icon: FlucordIcons.report,
              tooltip: 'Report message',
              onPressed: onReport!,
            ),
          if (capabilities.pinMessages)
            _ActionButton(
              icon: message.isPinned ? FlucordIcons.unpin : FlucordIcons.pin,
              tooltip: message.isPinned ? 'Unpin' : 'Pin',
              onPressed: onTogglePin,
            ),
          if (canModerate)
            _ActionButton(
              icon: FlucordIcons.delete,
              tooltip: 'Delete',
              destructive: true,
              onPressed: onDelete,
            ),
          Builder(
            builder: (button) => _ActionButton(
              buttonKey: ValueKey('message-more-${message.id}'),
              icon: FlucordIcons.more,
              tooltip: 'More',
              onPressed: () {
                final box = button.findRenderObject()! as RenderBox;
                onMore(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _reactionPicker({
    required Key buttonKey,
    required EmojiPickerPurpose purpose,
    required ValueChanged<String> onSelected,
  }) {
    final channel = workspace.channelById(message.channelId);
    final space = workspace.spaceById(channel.spaceId);
    return EmojiPickerButton(
      buttonKey: buttonKey,
      spaceName: space.name,
      emojiSections: emojiSectionsFromWorkspace(workspace, channel.spaceId),
      purpose: purpose,
      dimension: buttonSize,
      iconSize: 16,
      onMenuStateChanged: onReactionPickerToggled,
      onSelected: onSelected,
      favorites: expressionFavorites,
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
  final FlucordIconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
    onPressed: onPressed,
    icon: FlucordIcon(
      icon,
      size: 16,
      color: destructive ? context.surfaces.danger : null,
    ),
    tooltip: tooltip,
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(
      shape: const RoundedRectangleBorder(borderRadius: FlucordRadius.control),
    ),
    constraints: const BoxConstraints.tightFor(
      width: MessageActionBar.buttonSize,
      height: MessageActionBar.buttonSize,
    ),
  );
}
