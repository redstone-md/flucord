import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'message_item.dart';

class MessageList extends StatefulWidget {
  const MessageList({
    required this.workspace,
    required this.channel,
    required this.query,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReaction,
    required this.onAddReaction,
    super.key,
  });

  final ChatWorkspace workspace;
  final ConversationChannel channel;
  final String query;
  final ValueChanged<ChatMessage> onReply;
  final Future<bool> Function(ChatMessage, String) onEdit;
  final Future<void> Function(ChatMessage) onDelete;
  final Future<void> Function(ChatMessage, MessageReaction) onToggleReaction;
  final Future<void> Function(ChatMessage, String) onAddReaction;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scrollController = ScrollController();
  int _previousCount = 0;

  @override
  void initState() {
    super.initState();
    _previousCount = _visibleMessages.length;
    _scrollToEnd(jump: true);
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = _visibleMessages.length;
    final channelChanged = oldWidget.channel.id != widget.channel.id;
    if (channelChanged || count > _previousCount) {
      _scrollToEnd(jump: channelChanged);
    }
    _previousCount = count;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<ChatMessage> get _visibleMessages {
    final messages = widget.workspace.messagesFor(widget.channel.id);
    final query = widget.query.trim().toLowerCase();
    if (query.isEmpty) return messages;
    return messages
        .where((message) {
          final author = widget.workspace.memberById(message.authorId);
          return message.body.toLowerCase().contains(query) ||
              author.displayName.toLowerCase().contains(query) ||
              message.attachments.any(
                (attachment) =>
                    attachment.fileName.toLowerCase().contains(query),
              );
        })
        .toList(growable: false);
  }

  void _scrollToEnd({required bool jump}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = _visibleMessages;
    if (messages.isEmpty) {
      return _MessageEmptyState(hasQuery: widget.query.trim().isNotEmpty);
    }
    return ListView.builder(
      key: ValueKey('messages-${widget.channel.id}'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 22),
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _ChannelStart(channel: widget.channel);
        final message = messages[index - 1];
        final previous = index > 1 ? messages[index - 2] : null;
        final grouped =
            message.reply == null &&
            previous != null &&
            previous.authorId == message.authorId &&
            message.sentAt.difference(previous.sentAt).inMinutes < 7;
        return MessageItem(
          key: ValueKey('message-${message.id}'),
          message: message,
          member: widget.workspace.memberById(message.authorId),
          workspace: widget.workspace,
          grouped: grouped,
          isCurrentUser: message.authorId == widget.workspace.currentMemberId,
          onReply: widget.onReply,
          onEdit: widget.onEdit,
          onDelete: widget.onDelete,
          onToggleReaction: widget.onToggleReaction,
          onAddReaction: widget.onAddReaction,
        );
      },
    );
  }
}

class _ChannelStart extends StatelessWidget {
  const _ChannelStart({required this.channel});

  final ConversationChannel channel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            channel.isThread ? Icons.forum_outlined : Icons.tag,
            size: 28,
            color: context.surfaces.muted,
          ),
          const SizedBox(height: 12),
          Text(
            '${channel.isThread ? '' : '# '}${channel.name}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            channel.topic,
            style: TextStyle(color: context.surfaces.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _MessageEmptyState extends StatelessWidget {
  const _MessageEmptyState({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off : Icons.forum_outlined,
              size: 30,
              color: context.surfaces.muted,
            ),
            const SizedBox(height: 12),
            Text(
              hasQuery ? 'No matching messages' : 'No messages yet',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              hasQuery
                  ? 'Try a different phrase, author, or filename.'
                  : 'Start the conversation from the field below.',
              style: TextStyle(color: context.surfaces.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
