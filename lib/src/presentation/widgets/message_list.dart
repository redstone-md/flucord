import '../../application/expression_favorites_controller.dart';
import '../../domain/automod_rule.dart';
import 'package:flutter/material.dart';
import '../../application/slash_command_controller.dart';
import '../../application/message_component_controller.dart';

import '../../domain/channel_capabilities.dart';
import '../../domain/chat_models.dart';
import '../../domain/attachment_download.dart';
import '../../domain/external_link_launcher.dart';
import '../../theme/flucord_theme.dart';
import 'message_item.dart';
import 'message_forward_dialog.dart';
import 'reaction_details_dialog.dart';
import 'system_message_item.dart';
import 'unread_message_boundary.dart';

part 'message_list_states.dart';

class MessageList extends StatefulWidget {
  const MessageList({
    required this.workspace,
    this.componentController,
    this.applicationCommands,
    this.expressionFavorites,
    required this.channel,
    required this.query,
    required this.targetMessageId,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReaction,
    required this.onLoadReactionUsers,
    required this.onAddReaction,
    required this.onCreateThread,
    required this.onTogglePin,
    this.onResolveAlert,
    this.onReport,
    required this.onEndPoll,
    required this.onForward,
    required this.onToggleSuppressEmbeds,
    required this.canLoadOlder,
    required this.isLoadingOlder,
    required this.olderLoadError,
    required this.onLoadOlder,
    required this.externalLinkLauncher,
    required this.onSelectChannel,
    this.capabilities = ChannelCapabilities.unrestricted,
    this.attachmentDownloadService,
    super.key,
  });

  /// The starred expressions, when the transport holds any.
  final ExpressionFavoritesController? expressionFavorites;
  final ChatWorkspace workspace;

  /// Interaction planes, threaded through to each message: the buttons an
  /// application put on it, and the Apps menu that acts on it.
  final MessageComponentController? componentController;
  final SlashCommandController? applicationCommands;
  final ConversationChannel channel;

  /// Which per-message actions this channel's permissions allow.
  final ChannelCapabilities capabilities;
  final String query;
  final String? targetMessageId;
  final ValueChanged<ChatMessage> onReply;
  final Future<bool> Function(ChatMessage, String) onEdit;
  final Future<void> Function(ChatMessage) onDelete;
  final Future<void> Function(ChatMessage, MessageReaction) onToggleReaction;
  final ReactionUsersLoader onLoadReactionUsers;
  final Future<void> Function(ChatMessage, String) onAddReaction;
  final Future<bool> Function(ChatMessage, String, int) onCreateThread;
  final Future<void> Function(ChatMessage) onTogglePin;
  final Future<void> Function(ChatMessage, AutoModAlertAction)? onResolveAlert;

  /// Opens the report flow for a message, or null where there is none.
  final void Function(ChatMessage)? onReport;
  final Future<bool> Function(ChatMessage) onEndPoll;
  final ForwardMessageCallback onForward;
  final Future<bool> Function(ChatMessage) onToggleSuppressEmbeds;
  final bool canLoadOlder;
  final bool isLoadingOlder;
  final Object? olderLoadError;
  final VoidCallback onLoadOlder;
  final ExternalLinkLauncher externalLinkLauncher;
  final ValueChanged<String> onSelectChannel;
  final AttachmentDownloadService? attachmentDownloadService;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};

  /// The sliver the viewport is built around. What sits above it is laid out
  /// upward from it and what sits below downward, so adding history at either
  /// end leaves everything on screen where it was.
  final GlobalKey _centreKey = GlobalKey(debugLabel: 'message-centre');

  /// A message this list was asked to jump to from inside itself, such as a
  /// system message pointing at the message it talks about.
  String? _pinnedMessageId;
  bool _didReachUnread = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _messageKeys.clear();
      _pinnedMessageId = null;
      _didReachUnread = false;
      return;
    }
    if (oldWidget.channel.firstUnreadMessageId !=
        widget.channel.firstUnreadMessageId) {
      _didReachUnread = false;
    }
    if (oldWidget.targetMessageId != widget.targetMessageId &&
        widget.targetMessageId != null) {
      _pinnedMessageId = null;
      _returnToCentre();
    }
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

  /// The message the viewport is built around, or null to sit at the newest.
  String? get _anchorMessageId =>
      _pinnedMessageId ?? _targetMessageId ?? _unreadMessageId;

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

  /// Puts the viewport back on the message it is built around.
  ///
  /// Only a deliberate jump calls this. Arriving messages and loaded history
  /// never move the viewport, because they land on the far side of the centre.
  void _returnToCentre() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  void _jumpToMessage(String messageId) {
    setState(() => _pinnedMessageId = messageId);
    _returnToCentre();
  }

  void _handleScroll() {
    if (!_didReachUnread && _isUnreadBoundaryVisible()) {
      setState(() => _didReachUnread = true);
    }
    if (!_scrollController.hasClients ||
        !widget.canLoadOlder ||
        widget.isLoadingOlder ||
        widget.olderLoadError != null) {
      return;
    }
    // Older history sits above the centre, at offsets below zero, so the top
    // of the conversation is the minimum extent rather than offset zero.
    final position = _scrollController.position;
    if (position.pixels > position.minScrollExtent + 160) return;
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
    final anchorId = _anchorMessageId;
    final anchorIndex = anchorId == null
        ? -1
        : messages.indexWhere((message) => message.id == anchorId);
    // With no message to sit on, the centre goes past the newest message and
    // is pinned to the bottom edge, which is how a channel opens at its end.
    final centreIndex = anchorIndex < 0 ? messages.length : anchorIndex;
    final atEnd = centreIndex == messages.length;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomScrollView(
            key: ValueKey('messages-${widget.channel.id}'),
            controller: _scrollController,
            center: _centreKey,
            anchor: atEnd ? 1 : _anchorAlignment,
            slivers: [
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => index == centreIndex
                      ? _channelHead()
                      : _messageAt(messages, centreIndex - 1 - index),
                  childCount: centreIndex + 1,
                ),
              ),
              SliverToBoxAdapter(
                key: _centreKey,
                child: SizedBox(height: atEnd ? 22 : 0),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _messageAt(messages, centreIndex + index),
                  childCount: messages.length - centreIndex,
                ),
              ),
              if (!atEnd) const SliverToBoxAdapter(child: SizedBox(height: 22)),
            ],
          ),
        ),
        // Offered only while the boundary is somewhere else: a list built
        // around it is already showing it.
        if (_unreadMessageId != null &&
            !_didReachUnread &&
            anchorId != _unreadMessageId)
          Positioned(
            top: 10,
            right: 16,
            child: JumpToUnreadButton(
              onPressed: () => _jumpToMessage(_unreadMessageId!),
            ),
          ),
      ],
    );
  }

  /// Where the message the viewport is built around sits in it. Not flush
  /// against the top edge: a little of what came before it reads as context.
  static const double _anchorAlignment = 0.16;

  /// What sits above the oldest held message: the start of the channel, or
  /// the control that asks for more of its history.
  Widget _channelHead() => Padding(
    padding: const EdgeInsets.only(top: 18),
    child:
        !widget.canLoadOlder &&
            !widget.isLoadingOlder &&
            widget.olderLoadError == null
        ? _ChannelStart(channel: widget.channel)
        : _HistoryBoundary(
            isLoading: widget.isLoadingOlder,
            error: widget.olderLoadError,
            onLoad: widget.onLoadOlder,
          ),
  );

  Widget _messageAt(List<ChatMessage> messages, int index) {
    final message = messages[index];
    final previous = index > 0 ? messages[index - 1] : null;
    final startsUnread = message.id == _unreadMessageId;
    final grouped =
        !startsUnread &&
        !message.isSystem &&
        message.reply == null &&
        previous != null &&
        !previous.isSystem &&
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
            if (message.isSystem)
              SystemMessageItem(
                key: ValueKey('message-${message.id}'),
                message: message,
                member: widget.workspace.memberById(message.authorId),
                workspace: widget.workspace,
                onJumpToMessage: _jumpToMessage,
                onSelectChannel: widget.onSelectChannel,
              )
            else
              MessageItem(
                componentController: widget.componentController,
                applicationCommands: widget.applicationCommands,
                expressionFavorites: widget.expressionFavorites,
                key: ValueKey('message-${message.id}'),
                message: message,
                member: widget.workspace.memberById(message.authorId),
                workspace: widget.workspace,
                capabilities: widget.capabilities,
                grouped: grouped,
                isCurrentUser:
                    message.authorId == widget.workspace.currentMemberId,
                onReply: widget.onReply,
                onEdit: widget.onEdit,
                onDelete: widget.onDelete,
                onToggleReaction: widget.onToggleReaction,
                onLoadReactionUsers: widget.onLoadReactionUsers,
                onAddReaction: widget.onAddReaction,
                onCreateThread: widget.onCreateThread,
                onTogglePin: widget.onTogglePin,
                onResolveAlert: widget.onResolveAlert,
                onReport: widget.onReport,
                onEndPoll: widget.onEndPoll,
                onForward: widget.onForward,
                onToggleSuppressEmbeds: widget.onToggleSuppressEmbeds,
                linkLauncher: widget.externalLinkLauncher,
                onSelectChannel: widget.onSelectChannel,
                attachmentDownloadService: widget.attachmentDownloadService,
              ),
          ],
        ),
      ),
    );
  }
}
