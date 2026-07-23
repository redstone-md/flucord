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
    required this.onTogglePin,
    required this.canLoadOlder,
    required this.isLoadingOlder,
    required this.olderLoadError,
    required this.onLoadOlder,
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
  final Future<void> Function(ChatMessage) onTogglePin;
  final bool canLoadOlder;
  final bool isLoadingOlder;
  final Object? olderLoadError;
  final VoidCallback onLoadOlder;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final _AnchoredScrollController _scrollController =
      _AnchoredScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  bool _readyForHistoryPaging = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _scrollToEnd(jump: true);
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousMessages = _visibleMessagesFor(oldWidget);
    final messages = _visibleMessages;
    final channelChanged = oldWidget.channel.id != widget.channel.id;
    final previousFirstId = previousMessages.isEmpty
        ? null
        : previousMessages.first.id;
    final prepended =
        !channelChanged &&
        previousFirstId != null &&
        messages.length > previousMessages.length &&
        messages.first.id != previousFirstId &&
        messages.any((message) => message.id == previousFirstId);
    final anchor = prepended ? _captureVisibleAnchor(previousMessages) : null;
    if (channelChanged) {
      _messageKeys.clear();
      _readyForHistoryPaging = false;
      _scrollToEnd(jump: true);
    } else if (anchor != null && _scrollController.hasClients) {
      _preserveScrollAfterPrepend(anchor, remainingPasses: 3);
    } else if (messages.length > previousMessages.length) {
      _scrollToEnd(jump: false);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  List<ChatMessage> get _visibleMessages => _visibleMessagesFor(widget);

  List<ChatMessage> _visibleMessagesFor(MessageList source) {
    final messages = source.workspace.messagesFor(source.channel.id);
    final query = source.query.trim().toLowerCase();
    if (query.isEmpty) return messages;
    return messages
        .where((message) {
          final author = source.workspace.memberById(message.authorId);
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
      _readyForHistoryPaging = true;
    });
  }

  ({GlobalKey key, double top})? _captureVisibleAnchor(
    List<ChatMessage> messages,
  ) {
    final viewport = _scrollController.position.context.notificationContext
        ?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    ({GlobalKey key, double top})? partial;
    for (final message in messages) {
      final key = _messageKeys[message.id];
      final renderObject = key?.currentContext?.findRenderObject();
      if (key == null || renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = top + renderObject.size.height;
      if (bottom <= viewportTop || top >= viewportBottom) continue;
      final candidate = (key: key, top: top);
      if (top >= viewportTop) return candidate;
      partial ??= candidate;
    }
    return partial;
  }

  void _preserveScrollAfterPrepend(
    ({GlobalKey key, double top}) anchor, {
    required int remainingPasses,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final renderObject = anchor.key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final displacement =
          renderObject.localToGlobal(Offset.zero).dy - anchor.top;
      _scrollController.shiftBy(displacement);
      if (remainingPasses > 1 && displacement.abs() > 0.5) {
        _preserveScrollAfterPrepend(
          anchor,
          remainingPasses: remainingPasses - 1,
        );
        WidgetsBinding.instance.scheduleFrame();
      }
    });
  }

  void _handleScroll() {
    if (!_readyForHistoryPaging ||
        !_scrollController.hasClients ||
        _scrollController.offset > 160 ||
        !widget.canLoadOlder ||
        widget.isLoadingOlder ||
        widget.olderLoadError != null) {
      return;
    }
    widget.onLoadOlder();
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
        if (index == 0) {
          if (!widget.canLoadOlder &&
              !widget.isLoadingOlder &&
              widget.olderLoadError == null) {
            return _ChannelStart(channel: widget.channel);
          }
          return _HistoryBoundary(
            isLoading: widget.isLoadingOlder,
            error: widget.olderLoadError,
            onLoad: widget.onLoadOlder,
          );
        }
        final message = messages[index - 1];
        final previous = index > 1 ? messages[index - 2] : null;
        final grouped =
            message.reply == null &&
            previous != null &&
            previous.authorId == message.authorId &&
            message.sentAt.difference(previous.sentAt).inMinutes < 7;
        return KeyedSubtree(
          key: _messageKeys.putIfAbsent(
            message.id,
            () => GlobalKey(debugLabel: 'message-anchor-${message.id}'),
          ),
          child: MessageItem(
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
            onTogglePin: widget.onTogglePin,
          ),
        );
      },
    );
  }
}

final class _AnchoredScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _AnchoredScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    keepScrollOffset: keepScrollOffset,
    debugLabel: debugLabel,
  );

  void shiftBy(double displacement) {
    if (!hasClients || displacement.abs() <= 0.5) return;
    (position as _AnchoredScrollPosition).shiftBy(displacement);
  }
}

final class _AnchoredScrollPosition extends ScrollPositionWithSingleContext {
  _AnchoredScrollPosition({
    required super.physics,
    required super.context,
    required super.oldPosition,
    required super.keepScrollOffset,
    required super.debugLabel,
  });

  void shiftBy(double displacement) {
    goIdle();
    forcePixels(pixels + displacement);
  }
}

class _HistoryBoundary extends StatelessWidget {
  const _HistoryBoundary({
    required this.isLoading,
    required this.error,
    required this.onLoad,
  });

  final bool isLoading;
  final Object? error;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('history-boundary'),
      height: 48,
      child: Center(
        child: isLoading
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : error != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Older messages unavailable',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const ValueKey('retry-older-messages'),
                    onPressed: onLoad,
                    tooltip: 'Retry older messages',
                    icon: const Icon(Icons.refresh, size: 16),
                  ),
                ],
              )
            : TextButton.icon(
                key: const ValueKey('load-older-messages'),
                onPressed: onLoad,
                icon: const Icon(Icons.arrow_upward, size: 14),
                label: const Text(
                  'Load older messages',
                  style: TextStyle(fontSize: 10),
                ),
              ),
      ),
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
