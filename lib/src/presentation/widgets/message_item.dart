import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/chat_models.dart';
import '../../domain/external_link_launcher.dart';
import '../../theme/flucord_theme.dart';
import 'create_thread_dialog.dart';
import 'emoji_picker.dart';
import 'member_avatar.dart';
import 'message_attachment_view.dart';
import 'message_content_view.dart';
import 'message_embed_view.dart';
import 'message_poll_view.dart';
import 'message_sticker_view.dart';
import 'remote_identity_image.dart';

class MessageItem extends StatefulWidget {
  const MessageItem({
    required this.message,
    required this.member,
    required this.workspace,
    required this.grouped,
    required this.isCurrentUser,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReaction,
    required this.onAddReaction,
    required this.onCreateThread,
    required this.onTogglePin,
    required this.onEndPoll,
    required this.linkLauncher,
    required this.onSelectChannel,
    super.key,
  });

  final ChatMessage message;
  final Member member;
  final ChatWorkspace workspace;
  final bool grouped;
  final bool isCurrentUser;
  final ValueChanged<ChatMessage> onReply;
  final Future<bool> Function(ChatMessage, String) onEdit;
  final Future<void> Function(ChatMessage) onDelete;
  final Future<void> Function(ChatMessage, MessageReaction) onToggleReaction;
  final Future<void> Function(ChatMessage, String) onAddReaction;
  final Future<bool> Function(ChatMessage, String, int) onCreateThread;
  final Future<void> Function(ChatMessage) onTogglePin;
  final Future<bool> Function(ChatMessage) onEndPoll;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;

  @override
  State<MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<MessageItem> {
  bool _hovered = false;
  bool _editing = false;
  bool _reactionPickerOpen = false;
  late final TextEditingController _editController = TextEditingController(
    text: widget.message.body,
  );
  final FocusNode _editFocus = FocusNode();

  @override
  void didUpdateWidget(covariant MessageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.message.body != widget.message.body) {
      _editController.text = widget.message.body;
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  Future<void> _saveEdit() async {
    final content = _editController.text.trim();
    if (content.isEmpty) return;
    final saved = await widget.onEdit(widget.message, content);
    if (mounted && saved) setState(() => _editing = false);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onDelete(widget.message);
  }

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(widget.message.sentAt);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _hovered
                  ? context.surfaces.raised.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
            padding: EdgeInsets.fromLTRB(20, widget.grouped ? 3 : 9, 20, 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 38,
                  child: widget.grouped
                      ? Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            time,
                            style: TextStyle(
                              color: context.surfaces.muted,
                              fontSize: 9,
                            ),
                          ),
                        )
                      : MemberAvatar(
                          member: widget.member,
                          size: 34,
                          spaceId: widget.workspace
                              .channelById(widget.message.channelId)
                              .spaceId,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _content(context, time)),
              ],
            ),
          ),
          if ((_hovered || _reactionPickerOpen) && !_editing)
            Positioned(right: 18, top: -12, child: _actionBar(context)),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, String time) {
    final message = widget.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.grouped) _authorLine(context, time),
        if (message.reply case final reply?) _replyLine(context, reply),
        if (_editing)
          _editField(context)
        else if (message.body.isNotEmpty)
          MessageContentView(
            body: message.body,
            workspace: widget.workspace,
            linkLauncher: widget.linkLauncher,
            onSelectChannel: widget.onSelectChannel,
          ),
        if (message.isEdited && !_editing)
          Text(
            '(edited)',
            style: TextStyle(color: context.surfaces.muted, fontSize: 9),
          ),
        for (final attachment in message.attachments)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: MessageAttachmentView(attachment: attachment),
          ),
        for (var index = 0; index < message.embeds.length; index++)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: MessageEmbedView(
              key: ValueKey('message-${message.id}-embed-$index'),
              embed: message.embeds[index],
              workspace: widget.workspace,
              linkLauncher: widget.linkLauncher,
              onSelectChannel: widget.onSelectChannel,
            ),
          ),
        if (message.stickers.isNotEmpty)
          MessageStickerStrip(stickers: message.stickers),
        if (message.poll case final poll?)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: MessagePollView(
              poll: poll,
              canEnd: widget.isCurrentUser,
              onEnd: () => unawaited(widget.onEndPoll(message)),
            ),
          ),
        if (message.reactions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final reaction in message.reactions)
                _reactionChip(context, reaction),
            ],
          ),
        ],
      ],
    );
  }

  Widget _authorLine(BuildContext context, String time) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        Text(
          widget.member.displayName,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Text(
          time,
          style: TextStyle(color: context.surfaces.muted, fontSize: 10),
        ),
      ],
    ),
  );

  Widget _replyLine(BuildContext context, MessageReply reply) {
    final author = widget.workspace.memberOrNull(reply.authorId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.subdirectory_arrow_right,
            size: 13,
            color: context.surfaces.muted,
          ),
          const SizedBox(width: 5),
          Text(
            author?.displayName ?? 'Unknown user',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              reply.body.isEmpty ? 'Message unavailable' : reply.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.surfaces.muted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editField(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _saveEdit,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            setState(() => _editing = false);
          },
        },
        child: TextField(
          key: ValueKey('edit-${widget.message.id}'),
          controller: _editController,
          focusNode: _editFocus,
          autofocus: true,
          maxLines: 4,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Escape to cancel · Enter to save',
        style: TextStyle(color: context.surfaces.muted, fontSize: 9),
      ),
    ],
  );

  Widget _reactionChip(BuildContext context, MessageReaction reaction) =>
      Semantics(
        label: '${reaction.emojiName} reaction, ${reaction.count}',
        button: true,
        toggled: reaction.reactedByCurrentUser,
        onTap: () => widget.onToggleReaction(widget.message, reaction),
        excludeSemantics: true,
        child: Material(
          color: reaction.reactedByCurrentUser
              ? FlucordColors.brand.withValues(alpha: 0.16)
              : context.surfaces.inset,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: () => widget.onToggleReaction(widget.message, reaction),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                border: Border.all(
                  color: reaction.reactedByCurrentUser
                      ? FlucordColors.brand.withValues(alpha: 0.65)
                      : context.surfaces.border,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _reactionGlyph(reaction),
                  const SizedBox(width: 5),
                  Text(
                    '${reaction.count}',
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _reactionGlyph(MessageReaction reaction) {
    final emoji = _guildEmojiFor(reaction);
    if (emoji == null) {
      return Text(reaction.emojiName, style: const TextStyle(fontSize: 12));
    }
    return SizedBox.square(
      key: ValueKey('reaction-custom-${widget.message.id}-${reaction.emojiId}'),
      dimension: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: RemoteIdentityImage(
          url: emoji.imageUrl,
          fallback: ColoredBox(
            color: context.surfaces.raised,
            child: Center(
              child: Text(
                emoji.name.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  GuildEmoji? _guildEmojiFor(MessageReaction reaction) {
    final id = reaction.emojiId;
    if (id == null) return null;
    final spaceId = widget.workspace
        .channelById(widget.message.channelId)
        .spaceId;
    for (final emoji in widget.workspace.emojisFor(spaceId)) {
      if (emoji.id == id) return emoji;
    }
    return null;
  }

  Widget _actionBar(BuildContext context) => Container(
    height: 30,
    decoration: BoxDecoration(
      color: context.surfaces.surface,
      border: Border.all(color: context.surfaces.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.reply,
          tooltip: 'Reply',
          onPressed: () => widget.onReply(widget.message),
        ),
        _reactionPicker(),
        if (_canCreateThread)
          _ActionButton(
            buttonKey: ValueKey('create-thread-${widget.message.id}'),
            icon: Icons.forum_outlined,
            tooltip: 'Create thread',
            onPressed: _showCreateThreadDialog,
          ),
        if (widget.isCurrentUser)
          _ActionButton(
            icon: Icons.edit_outlined,
            tooltip: 'Edit',
            onPressed: () {
              setState(() => _editing = true);
              _editFocus.requestFocus();
            },
          ),
        _ActionButton(
          icon: widget.message.isPinned
              ? Icons.push_pin
              : Icons.push_pin_outlined,
          tooltip: widget.message.isPinned ? 'Unpin' : 'Pin',
          onPressed: () => widget.onTogglePin(widget.message),
        ),
        _ActionButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete',
          destructive: true,
          onPressed: _confirmDelete,
        ),
      ],
    ),
  );

  Widget _reactionPicker() {
    final channel = widget.workspace.channelById(widget.message.channelId);
    final space = widget.workspace.spaceById(channel.spaceId);
    return EmojiPickerButton(
      buttonKey: ValueKey('add-reaction-${widget.message.id}'),
      spaceName: space.name,
      customEmojis: widget.workspace.emojisFor(space.id),
      purpose: EmojiPickerPurpose.reaction,
      dimension: 30,
      iconSize: 16,
      onMenuStateChanged: (isOpen) {
        if (mounted) setState(() => _reactionPickerOpen = isOpen);
      },
      onSelected: (emoji) =>
          unawaited(widget.onAddReaction(widget.message, emoji)),
    );
  }

  bool get _canCreateThread {
    final channel = widget.workspace.channelById(widget.message.channelId);
    return !channel.isThread &&
        !widget.workspace.spaceById(channel.spaceId).isDirectMessages;
  }

  void _showCreateThreadDialog() {
    unawaited(
      CreateThreadDialog.show(
        context,
        onCreate: (name, duration) =>
            widget.onCreateThread(widget.message, name, duration),
      ),
    );
  }

  static String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
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
