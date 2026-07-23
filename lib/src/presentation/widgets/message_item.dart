import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/chat_models.dart';
import '../../domain/external_link_launcher.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';
import 'message_attachment_view.dart';
import 'message_content_view.dart';
import 'message_embed_view.dart';

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
    required this.onTogglePin,
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
  final Future<void> Function(ChatMessage) onTogglePin;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;

  @override
  State<MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<MessageItem> {
  static const _quickReactions = ['👍', '❤️', '😂', '🔥', '✓'];

  bool _hovered = false;
  bool _editing = false;
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
              border: widget.isCurrentUser
                  ? const Border(
                      left: BorderSide(color: FlucordColors.signal, width: 2),
                    )
                  : null,
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
          if (_hovered && !_editing)
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
      Material(
        color: reaction.reactedByCurrentUser
            ? FlucordColors.signal.withValues(alpha: 0.16)
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
                    ? FlucordColors.signal.withValues(alpha: 0.65)
                    : context.surfaces.border,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(reaction.emojiName, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Text('${reaction.count}', style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ),
      );

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
        PopupMenuButton<String>(
          tooltip: 'Add reaction',
          icon: const Icon(Icons.add_reaction_outlined, size: 16),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          onSelected: (emoji) =>
              unawaited(widget.onAddReaction(widget.message, emoji)),
          itemBuilder: (_) => [
            for (final emoji in _quickReactions)
              PopupMenuItem(value: emoji, child: Text(emoji)),
          ],
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

  static String _formatTime(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => IconButton(
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
