import '../../application/expression_favorites_controller.dart';
import '../../domain/automod_rule.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../application/slash_command_controller.dart';
import '../../application/message_component_controller.dart';

import '../../domain/channel_capabilities.dart';
import '../../domain/chat_models.dart';
import '../../domain/attachment_download.dart';
import '../../domain/external_link_launcher.dart';
import '../../domain/navigation_memory.dart';
import '../../theme/flucord_theme.dart';
import 'message_day_divider.dart';
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
    this.targetRequest = 0,
    this.lastSentMessageId,
    this.hasNewerMessages = false,
    this.windowError,
    this.readingPositions,
    required this.onOpenMessage,
    required this.onLoadPresent,
    required this.onReply,
    required this.onEdit,
    this.onEditClosed,
    required this.onDelete,
    required this.onToggleReaction,
    required this.onLoadReactionUsers,
    required this.onAddReaction,
    this.onMarkUnread,
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
    this.onOpenMemberProfile,
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

  /// Changes with each jump, so a second jump to the same message lands again.
  final int targetRequest;

  /// Whether the held messages stop short of the present, because a jump took
  /// the reader to an older stretch of the channel.
  final bool hasNewerMessages;

  /// Why the last jump did not land. Each failure is a new object.
  final Object? windowError;

  /// Where the reader stopped in each channel. This list reads a channel's
  /// position when it opens, and keeps it up to date as the reader scrolls.
  final ReadingPositions? readingPositions;

  /// Jumps to a message of this channel, which may not be held yet.
  final ValueChanged<String> onOpenMessage;

  /// Loads the newest page when [hasNewerMessages] is true.
  final VoidCallback onLoadPresent;

  /// The message this client last sent in this channel. A new value takes a
  /// reader who has scrolled up to the end of the conversation.
  final String? lastSentMessageId;
  final ValueChanged<ChatMessage> onReply;
  final Future<bool> Function(ChatMessage, String) onEdit;

  /// An edit field closed, saved or not, and it was not opened from its row, so
  /// the keyboard can go back to where the next message is written.
  final VoidCallback? onEditClosed;
  final Future<void> Function(ChatMessage) onDelete;
  final Future<void> Function(ChatMessage, MessageReaction) onToggleReaction;
  final ReactionUsersLoader onLoadReactionUsers;
  final Future<void> Function(ChatMessage, String) onAddReaction;
  final Future<void> Function(ChatMessage)? onMarkUnread;
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

  /// Opens the profile of a message's author, by user id.
  final ValueChanged<String>? onOpenMemberProfile;
  final AttachmentDownloadService? attachmentDownloadService;

  @override
  State<MessageList> createState() => MessageListState();
}

/// Where the viewport's centre sits, named by a message so that rows added on
/// either side cannot move it.
final class _TimelineCentre {
  /// The centre sits just above [message], which opens the viewport.
  const _TimelineCentre.above(this.message) : isBelowMessage = false;

  /// The centre sits just below [message], the newest when it was captured, so
  /// the viewport opens on the end of the conversation.
  const _TimelineCentre.below(this.message) : isBelowMessage = true;

  final ChatMessage message;
  final bool isBelowMessage;

  /// How many of [messages] sit above the centre.
  int indexIn(List<ChatMessage> messages) {
    final held = messages.lastIndexWhere((other) => other.id == message.id);
    if (held >= 0) return isBelowMessage ? held + 1 : held;
    // The message was deleted, or a refresh replaced it. Its place stays.
    final next = messages.indexWhere(
      (other) => other.sentAt.isAfter(message.sentAt),
    );
    return next < 0 ? messages.length : next;
  }
}

/// Names a row by its message, so a sliver list can find where the row went
/// when rows around it change.
final class _MessageRowKey extends GlobalKey {
  const _MessageRowKey(this.messageId) : super.constructor();

  final String messageId;
}

/// Public so the conversation pane can reach the list through a global key: the
/// keyboard works from outside this widget.
class MessageListState extends State<MessageList>
    with SingleTickerProviderStateMixin {
  /// Where the message the viewport is built around sits in it. Not flush
  /// against the top edge: a little of what came before it reads as context.
  static const double _anchorAlignment = 0.16;

  /// The space under the newest message.
  static const double _endGap = 22;

  /// A reader this close to the end counts as being at the end.
  static const double _endTolerance = 8;

  /// How strongly a jump's target is tinted when the reader lands on it.
  static const double _highlightAlpha = 0.08;

  /// The whole life of the highlight. It holds for the first half, so the eye
  /// can find the row, and fades over the second.
  static const Duration _highlightDuration = Duration(seconds: 2);

  static const _headKey = ValueKey('message-list-head');

  final ScrollController _scrollController = ScrollController();
  final Map<String, _MessageRowKey> _messageKeys = {};

  /// The sliver the viewport is built around. What sits above it is laid out
  /// upward from it and what sits below downward, so adding history at either
  /// end leaves everything on screen where it was.
  final GlobalKey _centreKey = GlobalKey(debugLabel: 'message-centre');

  /// Captured once when the channel opens, and changed only by an explicit
  /// jump. Null until there is a message to name.
  _TimelineCentre? _centre;

  /// The message a jump is waiting for. It becomes the centre as soon as the
  /// list holds it, unless the reader scrolls first.
  String? _awaitedMessageId;

  /// The saved position this opening is on its way to, until it lands or the
  /// reader scrolls.
  ReadingPosition? _restoring;

  /// How far below the top of the timeline the centre sits, when a restored
  /// position decides that. Otherwise [_anchorAlignment] does.
  double? _centreFromTop;
  bool _isKeepingPosition = false;

  /// Counts the scrollables this list has made. Each explicit jump starts a
  /// new one, whose first frame is already at the new centre.
  int _viewportGeneration = 0;

  /// The row a jump last landed on, and how far its highlight has faded.
  String? _highlightedMessageId;
  late final AnimationController _highlight;
  late final Animation<double> _highlightFade;

  /// The one row showing its edit field.
  String? _editingMessageId;

  bool _didReachUnread = false;

  /// Whether the reader is at the newest message. While true, the list follows
  /// any growth below them, whatever caused it.
  bool _isAtEnd = true;

  @override
  void initState() {
    super.initState();
    _highlight = AnimationController(vsync: this, duration: _highlightDuration);
    _highlightFade = CurvedAnimation(
      parent: _highlight,
      curve: const Interval(0.5, 1, curve: Curves.easeOut),
    );
    _scrollController.addListener(_handleScroll);
    _openChannel();
  }

  @override
  void didUpdateWidget(covariant MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _messageKeys.clear();
      _editingMessageId = null;
      _didReachUnread = false;
      _openChannel();
      return;
    }
    if (oldWidget.query.trim() != widget.query.trim()) {
      _recentre(awaiting: _openingMessageId);
    }
    // The saved position's message is gone, so this opening goes on as if there
    // had been no position.
    if (_restoring != null &&
        widget.readingPositions?.of(widget.channel.id) == null) {
      _awaitedMessageId = _openingMessageId;
      _restoring = null;
    }
    final oldUnreadId = oldWidget.channel.firstUnreadMessageId;
    if (oldUnreadId != widget.channel.firstUnreadMessageId) {
      _didReachUnread = false;
      // The boundary moving is no jump. It only matters to a list still
      // waiting to open on it.
      if (oldUnreadId != null && _awaitedMessageId == oldUnreadId) {
        _awaitedMessageId = _unreadMessageId;
      }
    }
    // A window on the first unread message replaced the page this list opened
    // on, which had no message that far back.
    if (!oldWidget.hasNewerMessages &&
        widget.hasNewerMessages &&
        _targetMessageId == null) {
      _awaitedMessageId = _restoring?.messageId ?? _unreadMessageId;
    }
    if ((oldWidget.targetMessageId != widget.targetMessageId ||
            oldWidget.targetRequest != widget.targetRequest) &&
        widget.targetMessageId != null) {
      _awaitedMessageId = _targetMessageId;
    }
    if (widget.windowError != null &&
        !identical(oldWidget.windowError, widget.windowError)) {
      _awaitedMessageId = null;
      _reportFailedJump();
    }
    // The newest page replaced an old window. A jump still on its way decides
    // where the reader goes instead.
    if (oldWidget.hasNewerMessages &&
        !widget.hasNewerMessages &&
        _awaitedMessageId == null) {
      _recentre();
    }
    if (oldWidget.lastSentMessageId != widget.lastSentMessageId &&
        widget.lastSentMessageId != null &&
        !_isAtEnd) {
      _recentre();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _highlight.dispose();
    super.dispose();
  }

  List<ChatMessage> get _visibleMessages => _visibleMessagesFor(widget);

  String? get _unreadMessageId =>
      widget.query.trim().isEmpty ? widget.channel.firstUnreadMessageId : null;

  String? get _targetMessageId =>
      widget.query.trim().isEmpty ? widget.targetMessageId : null;

  /// The message a channel opens on, or null to open at the newest.
  String? get _openingMessageId => _targetMessageId ?? _unreadMessageId;

  /// Opens the channel on a jump's target if there is one, then on the place the
  /// reader left it, and only then on its unread boundary. A reader who left a
  /// position chose it, and the NEW line still shows further down.
  void _openChannel() {
    final saved = _targetMessageId == null && widget.query.trim().isEmpty
        ? widget.readingPositions?.of(widget.channel.id)
        : null;
    _recentre(awaiting: saved?.messageId ?? _openingMessageId);
    _restoring = saved;
  }

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

  void _setEditing(String messageId, {required bool editing}) {
    if (!mounted) return;
    if (editing) {
      setState(() => _editingMessageId = messageId);
      return;
    }
    if (_editingMessageId == messageId) {
      setState(() => _editingMessageId = null);
    }
  }

  /// Opens the account's newest message that can be edited, and answers whether
  /// there is one. A row that is not built yet is reached by a jump. One that
  /// is built brings itself into view when its field takes the focus.
  bool editLastOwnMessage() {
    final own = _visibleMessages
        .where(
          (message) =>
              message.authorId == widget.workspace.currentMemberId &&
              message.canEdit &&
              !message.isSystem,
        )
        .lastOrNull;
    if (own == null) return false;
    setState(() {
      _editingMessageId = own.id;
      if (_messageKeys[own.id]?.currentContext == null) {
        _awaitedMessageId = own.id;
      }
    });
    return true;
  }

  /// Moves the timeline by most of a screen. A negative [direction] goes toward
  /// older messages.
  void scrollPage(int direction) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // A reader who moved has chosen a place, and a late page must not take it.
    _awaitedMessageId = null;
    position.jumpTo(
      (position.pixels + direction * position.viewportDimension * 0.9).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  /// Drops the centre, so the next build captures a new one in a new
  /// scrollable. With nothing to wait for, that is the end of the conversation.
  void _recentre({String? awaiting}) {
    _centre = null;
    _centreFromTop = null;
    _restoring = null;
    _awaitedMessageId = awaiting;
    _isAtEnd = awaiting == null;
    _viewportGeneration++;
  }

  /// The centre for this build. Only here does a held message that a jump was
  /// waiting for become the centre.
  _TimelineCentre _centreIn(List<ChatMessage> messages) {
    final awaitedId = _awaitedMessageId;
    final awaited = awaitedId == null
        ? null
        : messages.where((message) => message.id == awaitedId).firstOrNull;
    if (awaited != null) {
      _awaitedMessageId = null;
      _isAtEnd = false;
      _viewportGeneration++;
      if (awaited.id == _targetMessageId) {
        _highlightedMessageId = awaited.id;
        _highlight.forward(from: 0);
      }
      final restored = _restoring;
      _restoring = null;
      _centreFromTop = restored?.messageId == awaited.id
          ? restored?.fromTop
          : null;
      if (_centreFromTop == null) _forgetPosition();
      return _centre = _TimelineCentre.above(awaited);
    }
    // A new viewport at the end of the conversation. The place the reader was
    // before is behind them now, unless a saved position is still on its way.
    if (_centre == null && awaitedId == null) _forgetPosition();
    return _centre ??= _TimelineCentre.below(messages.last);
  }

  /// A channel opened at, or a reader jumped to, a place they did not scroll to.
  void _forgetPosition() =>
      widget.readingPositions?.keep(widget.channel.id, null);

  /// Answers the end of a scroll. The rows have not moved for its last step yet,
  /// so the position is read after the next layout.
  void _keepPositionAfterLayout() {
    if (_isKeepingPosition) return;
    _isKeepingPosition = true;
    final channelId = widget.channel.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isKeepingPosition = false;
      if (mounted && widget.channel.id == channelId) _keepPosition();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Saves where the reader is. An old window's end is a place too, because the
  /// present is further on.
  void _keepPosition() {
    final positions = widget.readingPositions;
    if (positions == null ||
        !_scrollController.hasClients ||
        _awaitedMessageId != null ||
        widget.query.trim().isNotEmpty) {
      return;
    }
    if (_isAtEnd && !widget.hasNewerMessages) {
      _forgetPosition();
      return;
    }
    final position = _positionOnScreen();
    if (position != null) positions.keep(widget.channel.id, position);
  }

  /// The first row that starts inside the timeline. With no such row, one row
  /// fills the timeline, and the reader comes back to its top.
  ReadingPosition? _positionOnScreen() {
    final timeline = _scrollController.position.context.notificationContext
        ?.findRenderObject();
    if (timeline is! RenderBox) return null;
    String? firstInside;
    var firstInsideTop = double.infinity;
    String? lastAbove;
    var lastAboveTop = double.negativeInfinity;
    for (final MapEntry(key: id, value: key) in _messageKeys.entries) {
      final row = key.currentContext?.findRenderObject();
      if (row is! RenderBox || !row.hasSize) continue;
      final top = row.localToGlobal(Offset.zero, ancestor: timeline).dy;
      if (top >= 0 && top < firstInsideTop) {
        firstInside = id;
        firstInsideTop = top;
      } else if (top < 0 && top > lastAboveTop) {
        lastAbove = id;
        lastAboveTop = top;
      }
    }
    if (firstInside != null && firstInsideTop < timeline.size.height) {
      return ReadingPosition(messageId: firstInside, fromTop: firstInsideTop);
    }
    return lastAbove == null
        ? null
        : ReadingPosition(messageId: lastAbove, fromTop: 0);
  }

  /// Takes the reader to the unread boundary, which may be outside a window.
  void _jumpToUnread(String messageId) {
    if (_visibleMessages.any((message) => message.id == messageId)) {
      setState(() => _awaitedMessageId = messageId);
    } else {
      widget.onOpenMessage(messageId);
    }
  }

  /// Takes the reader to the end of the conversation. From an old window that
  /// means loading it first, and the list recentres when the page is in.
  void jumpToPresent() {
    if (widget.hasNewerMessages) {
      widget.onLoadPresent();
    } else {
      setState(_recentre);
    }
  }

  void _reportFailedJump() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 72),
        content: Text("Couldn't load that part of the conversation."),
      ),
    );
  });

  void _recordWhetherAtEnd() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atEnd = position.pixels >= position.maxScrollExtent - _endTolerance;
    if (atEnd != _isAtEnd) setState(() => _isAtEnd = atEnd);
  }

  /// Answers a change in the size of the content or the viewport, which moves
  /// the end without scrolling anything. A reader who was at the end stays
  /// there. Anybody else stays where they are, and may now be at the end.
  bool _handleMetricsChange(ScrollMetricsNotification notification) {
    // A scrollable inside a row or its menu reports here too. Its numbers say
    // nothing about this list.
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    if (!_isAtEnd) {
      _recordWhetherAtEnd();
    } else if (metrics.pixels < metrics.maxScrollExtent) {
      _scrollController.jumpTo(metrics.maxScrollExtent);
    }
    return false;
  }

  void _handleScroll() {
    // A reader who moved has chosen a place, and a late page must not take it.
    if (_scrollController.position.userScrollDirection !=
        ScrollDirection.idle) {
      _awaitedMessageId = null;
      _restoring = null;
    }
    if (!_didReachUnread && _isUnreadBoundaryVisible()) {
      setState(() => _didReachUnread = true);
    }
    _recordWhetherAtEnd();
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
    final targetTop = target.localToGlobal(Offset.zero, ancestor: viewport).dy;
    return targetTop >= 0 && targetTop < viewport.size.height;
  }

  @override
  Widget build(BuildContext context) {
    final messages = _visibleMessages;
    if (messages.isEmpty) {
      return _MessageEmptyState(hasQuery: widget.query.trim().isNotEmpty);
    }
    // Keys outlive the messages they belong to when a refresh replaces the
    // held history, so the table is swept once it has outgrown the channel.
    if (_messageKeys.length > messages.length * 2) {
      final held = {for (final message in messages) message.id};
      _messageKeys.removeWhere((id, _) => !held.contains(id));
    }
    final centre = _centreIn(messages);
    final centreIndex = centre.indexIn(messages);
    // A rebuild asks where each mounted row went, so this is built only then.
    late final rowIndexes = {
      for (final (index, message) in messages.indexed) message.id: index,
    };
    int? rowIndex(Key key) =>
        key is _MessageRowKey ? rowIndexes[key.messageId] : null;
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollMetricsNotification>(
            key: ValueKey('messages-${widget.channel.id}'),
            onNotification: _handleMetricsChange,
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (_) {
                _keepPositionAfterLayout();
                return false;
              },
              child: LayoutBuilder(
                builder: (context, constraints) => CustomScrollView(
                  key: ValueKey(_viewportGeneration),
                  controller: _scrollController,
                  center: _centreKey,
                  // At the end of the conversation, the gap under the newest
                  // message fills the viewport below the centre. Offset zero is
                  // then the end, with the gap on screen.
                  anchor: centre.isBelowMessage
                      ? (1 - _endGap / constraints.maxHeight).clamp(0.0, 1.0)
                      : _anchorFor(constraints.maxHeight),
                  slivers: [
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => index == centreIndex
                            ? _channelHead()
                            : _messageAt(messages, centreIndex - 1 - index),
                        childCount: centreIndex + 1,
                        findChildIndexCallback: (key) {
                          if (key == _headKey) return centreIndex;
                          final row = rowIndex(key);
                          return row == null || row >= centreIndex
                              ? null
                              : centreIndex - 1 - row;
                        },
                      ),
                    ),
                    SliverToBoxAdapter(
                      key: _centreKey,
                      child: const SizedBox(),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _messageAt(messages, centreIndex + index),
                        childCount: messages.length - centreIndex,
                        findChildIndexCallback: (key) {
                          final row = rowIndex(key);
                          return row == null || row < centreIndex
                              ? null
                              : row - centreIndex;
                        },
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: _endGap)),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Offered only while the boundary is somewhere else: a list built
        // around it is already showing it.
        if (_unreadMessageId != null &&
            !_didReachUnread &&
            (centre.isBelowMessage || centre.message.id != _unreadMessageId))
          Positioned(
            top: 10,
            right: 16,
            child: JumpToUnreadButton(
              onPressed: () => _jumpToUnread(_unreadMessageId!),
            ),
          ),
        if (!_isAtEnd || widget.hasNewerMessages)
          Positioned(
            bottom: 10,
            right: 16,
            child: JumpToPresentButton(onPressed: jumpToPresent),
          ),
      ],
    );
  }

  /// Where the centre sits in a timeline [height] tall, when it opens on a
  /// message.
  double _anchorFor(double height) {
    final fromTop = _centreFromTop;
    if (fromTop == null || height <= 0) return _anchorAlignment;
    return (fromTop / height).clamp(0.0, 1.0);
  }

  /// What sits above the oldest held message: the start of the channel, or
  /// the control that asks for more of its history.
  Widget _channelHead() => Padding(
    key: _headKey,
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
    final startsDay =
        previous != null &&
        MessageDayDivider.between(previous.sentAt, message.sentAt);
    final grouped =
        !startsUnread &&
        !startsDay &&
        !message.isSystem &&
        message.reply == null &&
        previous != null &&
        !previous.isSystem &&
        previous.authorId == message.authorId &&
        message.sentAt.difference(previous.sentAt).inMinutes < 7;
    return KeyedSubtree(
      key: _messageKeys.putIfAbsent(
        message.id,
        () => _MessageRowKey(message.id),
      ),
      child: AnimatedBuilder(
        animation: _highlightFade,
        builder: (context, row) => ColoredBox(
          color: message.id == _highlightedMessageId
              ? context.surfaces.brand.withValues(
                  alpha: _highlightAlpha * (1 - _highlightFade.value),
                )
              : Colors.transparent,
          child: row,
        ),
        child: Column(
          children: [
            if (startsDay) MessageDayDivider(day: message.sentAt),
            if (startsUnread) const UnreadMessageBoundary(),
            if (message.isSystem)
              SystemMessageItem(
                key: ValueKey('message-${message.id}'),
                message: message,
                member: widget.workspace.memberById(message.authorId),
                workspace: widget.workspace,
                onJumpToMessage: widget.onOpenMessage,
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
                isEditing: message.id == _editingMessageId,
                onEditingChanged: (editing) =>
                    _setEditing(message.id, editing: editing),
                onEditClosed: widget.onEditClosed,
                onDelete: widget.onDelete,
                onToggleReaction: widget.onToggleReaction,
                onLoadReactionUsers: widget.onLoadReactionUsers,
                onAddReaction: widget.onAddReaction,
                onMarkUnread: widget.onMarkUnread,
                onCreateThread: widget.onCreateThread,
                onTogglePin: widget.onTogglePin,
                onResolveAlert: widget.onResolveAlert,
                onReport: widget.onReport,
                onEndPoll: widget.onEndPoll,
                onForward: widget.onForward,
                onToggleSuppressEmbeds: widget.onToggleSuppressEmbeds,
                linkLauncher: widget.externalLinkLauncher,
                onSelectChannel: widget.onSelectChannel,
                onOpenMemberProfile: widget.onOpenMemberProfile,
                onOpenMessage: widget.onOpenMessage,
                attachmentDownloadService: widget.attachmentDownloadService,
              ),
          ],
        ),
      ),
    );
  }
}
