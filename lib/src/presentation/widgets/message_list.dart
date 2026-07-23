import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/external_link_launcher.dart';
import '../../theme/flucord_theme.dart';
import 'anchored_scroll_controller.dart';
import 'message_item.dart';
import 'unread_message_boundary.dart';

part 'message_list_states.dart';

class MessageList extends StatefulWidget {
  const MessageList({
    required this.workspace,
    required this.channel,
    required this.query,
    required this.targetMessageId,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReaction,
    required this.onAddReaction,
    required this.onCreateThread,
    required this.onTogglePin,
    required this.onEndPoll,
    required this.canLoadOlder,
    required this.isLoadingOlder,
    required this.olderLoadError,
    required this.onLoadOlder,
    required this.externalLinkLauncher,
    required this.onSelectChannel,
    super.key,
  });

  final ChatWorkspace workspace;
  final ConversationChannel channel;
  final String query;
  final String? targetMessageId;
  final ValueChanged<ChatMessage> onReply;
  final Future<bool> Function(ChatMessage, String) onEdit;
  final Future<void> Function(ChatMessage) onDelete;
  final Future<void> Function(ChatMessage, MessageReaction) onToggleReaction;
  final Future<void> Function(ChatMessage, String) onAddReaction;
  final Future<bool> Function(ChatMessage, String, int) onCreateThread;
  final Future<void> Function(ChatMessage) onTogglePin;
  final Future<bool> Function(ChatMessage) onEndPoll;
  final bool canLoadOlder;
  final bool isLoadingOlder;
  final Object? olderLoadError;
  final VoidCallback onLoadOlder;
  final ExternalLinkLauncher externalLinkLauncher;
  final ValueChanged<String> onSelectChannel;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final AnchoredScrollController _scrollController = AnchoredScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  bool _readyForHistoryPaging = false;
  bool _didReachUnread = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _scheduleInitialPosition();
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousMessages = _visibleMessagesFor(oldWidget);
    final messages = _visibleMessages;
    final channelChanged = oldWidget.channel.id != widget.channel.id;
    final unreadChanged =
        oldWidget.channel.firstUnreadMessageId !=
        widget.channel.firstUnreadMessageId;
    final targetChanged = oldWidget.targetMessageId != widget.targetMessageId;
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
      _didReachUnread = false;
      _scheduleInitialPosition();
    } else if (targetChanged && _targetMessageId != null) {
      _scrollToMessage(_targetMessageId!, animate: false);
    } else if (unreadChanged && _unreadMessageId != null) {
      _didReachUnread = false;
      _scrollToUnread(animate: false);
    } else if (anchor != null && _scrollController.hasClients) {
      _preserveScrollAfterPrepend(anchor, remainingPasses: 3);
    } else if (messages.length > previousMessages.length) {
      _scrollToEnd(jump: false);
    }
    if (unreadChanged && _unreadMessageId == null) _didReachUnread = false;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  List<ChatMessage> get _visibleMessages => _visibleMessagesFor(widget);

  String? get _unreadMessageId =>
      widget.query.trim().isEmpty ? widget.channel.firstUnreadMessageId : null;

  String? get _targetMessageId =>
      widget.query.trim().isEmpty ? widget.targetMessageId : null;

  List<ChatMessage> _visibleMessagesFor(MessageList source) {
    final messages = source.workspace.messagesFor(source.channel.id);
    final query = source.query.trim().toLowerCase();
    if (query.isEmpty) return messages;
    return messages
        .where((message) {
          final author = source.workspace.memberById(message.authorId);
          return message.body.toLowerCase().contains(query) ||
              author.displayName.toLowerCase().contains(query) ||
              message.stickers.any(
                (sticker) => sticker.name.toLowerCase().contains(query),
              ) ||
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

  void _scheduleInitialPosition() {
    if (_targetMessageId case final String targetMessageId) {
      _scrollToMessage(targetMessageId, animate: false);
      return;
    }
    if (_unreadMessageId == null) {
      _scrollToEnd(jump: true);
      return;
    }
    _scrollToUnread(animate: false);
  }

  void _scrollToUnread({required bool animate, int attempt = 0}) {
    final messageId = _unreadMessageId;
    if (messageId == null) return;
    _scrollToMessage(
      messageId,
      animate: animate,
      attempt: attempt,
      marksUnread: true,
    );
  }

  void _scrollToMessage(
    String messageId, {
    required bool animate,
    int attempt = 0,
    bool marksUnread = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final messages = _visibleMessages;
      final index = messages.indexWhere((message) => message.id == messageId);
      if (index < 0) return;
      final key = _messageKeys.putIfAbsent(
        messageId,
        () => GlobalKey(debugLabel: 'message-anchor-$messageId'),
      );
      final targetContext = key.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.16,
          duration: animate ? const Duration(milliseconds: 180) : Duration.zero,
          curve: Curves.easeOut,
        );
        if (marksUnread && !_didReachUnread) {
          setState(() => _didReachUnread = true);
        }
        return;
      }
      final position = _scrollController.position;
      final fraction = (index + 1) / (messages.length + 1);
      final estimate = (position.maxScrollExtent * fraction).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (animate) {
        _scrollController.animateTo(
          estimate,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(estimate);
      }
      if (attempt < 4) {
        _scrollToMessage(
          messageId,
          animate: animate,
          attempt: attempt + 1,
          marksUnread: marksUnread,
        );
      }
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
    if (!_didReachUnread && _isUnreadBoundaryVisible()) {
      setState(() => _didReachUnread = true);
    }
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

  bool _isUnreadBoundaryVisible() {
    final messageId = _unreadMessageId;
    final target = messageId == null
        ? null
        : _messageKeys[messageId]?.currentContext?.findRenderObject();
    final viewport = _scrollController.position.context.notificationContext
        ?.findRenderObject();
    if (target is! RenderBox || viewport is! RenderBox) return false;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    final targetTop = target.localToGlobal(Offset.zero).dy;
    return targetTop >= viewportTop && targetTop < viewportBottom;
  }

  @override
  Widget build(BuildContext context) {
    final messages = _visibleMessages;
    if (messages.isEmpty) {
      return _MessageEmptyState(hasQuery: widget.query.trim().isNotEmpty);
    }
    return Stack(
      children: [
        Positioned.fill(
          child: ListView.builder(
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
              final startsUnread = message.id == _unreadMessageId;
              final grouped =
                  !startsUnread &&
                  message.reply == null &&
                  previous != null &&
                  previous.authorId == message.authorId &&
                  message.sentAt.difference(previous.sentAt).inMinutes < 7;
              return KeyedSubtree(
                key: _messageKeys.putIfAbsent(
                  message.id,
                  () => GlobalKey(debugLabel: 'message-anchor-${message.id}'),
                ),
                child: ColoredBox(
                  color: message.id == _targetMessageId
                      ? FlucordColors.brand.withValues(alpha: 0.08)
                      : Colors.transparent,
                  child: Column(
                    children: [
                      if (startsUnread) const UnreadMessageBoundary(),
                      MessageItem(
                        key: ValueKey('message-${message.id}'),
                        message: message,
                        member: widget.workspace.memberById(message.authorId),
                        workspace: widget.workspace,
                        grouped: grouped,
                        isCurrentUser:
                            message.authorId ==
                            widget.workspace.currentMemberId,
                        onReply: widget.onReply,
                        onEdit: widget.onEdit,
                        onDelete: widget.onDelete,
                        onToggleReaction: widget.onToggleReaction,
                        onAddReaction: widget.onAddReaction,
                        onCreateThread: widget.onCreateThread,
                        onTogglePin: widget.onTogglePin,
                        onEndPoll: widget.onEndPoll,
                        linkLauncher: widget.externalLinkLauncher,
                        onSelectChannel: widget.onSelectChannel,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_unreadMessageId != null && !_didReachUnread)
          Positioned(
            top: 10,
            right: 16,
            child: JumpToUnreadButton(
              onPressed: () => _scrollToUnread(animate: true),
            ),
          ),
      ],
    );
  }
}
