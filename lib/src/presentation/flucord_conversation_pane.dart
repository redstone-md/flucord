part of 'flucord_shell.dart';

/// A voice channel only behaves like a text channel while its chat surface is
/// the one on screen: the room has no timeline to search, pin, or type into.
/// Forum and media channels never qualify — their messages live in posts.
bool _showsMessageTimeline(
  ConversationChannel channel,
  VoiceChannelSurface voiceSurface,
) =>
    channel.hasMessageTimeline &&
    (channel.kind != ChannelKind.voice ||
        voiceSurface == VoiceChannelSurface.chat);

class _ConversationPane extends StatefulWidget {
  const _ConversationPane({
    required this.workspace,
    required this.externalLinkLauncher,
    required this.attachmentDownloadService,
    required this.channel,
    required this.channels,
    required this.query,
    required this.targetMessageId,
    required this.compact,
    required this.voiceSurface,
    required this.onSelectVoiceSurface,
    required this.onPickChannel,
    required this.allowMemberPanel,
    required this.allowThreadPanel,
    required this.showMembers,
    required this.showPins,
    required this.showThreads,
    required this.forumArchivedPosts,
    required this.isLoadingForumPosts,
    required this.forumPostsError,
    required this.canLoadMoreForumPosts,
    required this.inboxSummary,
    required this.typingMembers,
    required this.isSending,
    required this.isLoading,
    required this.loadError,
    required this.canLoadOlder,
    required this.isLoadingOlder,
    required this.olderLoadError,
    required this.onLoadOlder,
    required this.onRetry,
    required this.onSelectChannel,
    required this.onQueryChanged,
    required this.onToggleMembers,
    required this.onTogglePins,
    required this.onToggleThreads,
    required this.onRefreshForumPosts,
    required this.onLoadMoreForumPosts,
    required this.onLoadForumPostPreview,
    required this.onCreateForumPost,
    required this.onOpenInbox,
    required this.onSend,
    required this.onCreatePoll,
    required this.onSendStickers,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReaction,
    required this.onLoadReactionUsers,
    required this.onAddReaction,
    required this.onCreateThread,
    required this.onTogglePin,
    required this.onEndPoll,
    required this.onForward,
    required this.onToggleSuppressEmbeds,
    required this.onTyping,
    required this.voiceController,
    required this.voiceMessageRecorder,
    required this.onSendVoiceMessage,
  });

  final ChatWorkspace workspace;
  final ExternalLinkLauncher externalLinkLauncher;
  final AttachmentDownloadService attachmentDownloadService;
  final ConversationChannel channel;
  final List<ConversationChannel> channels;
  final String query;
  final String? targetMessageId;
  final bool compact;
  final VoiceChannelSurface voiceSurface;
  final ValueChanged<VoiceChannelSurface> onSelectVoiceSurface;

  /// The compact channel picker stands in for the channel sidebar, so it keeps
  /// a voice channel's own surface. [onSelectChannel] is the message-shaped
  /// route — mentions, forum posts — and lands on the timeline instead.
  final ValueChanged<String> onPickChannel;
  final bool allowMemberPanel;
  final bool allowThreadPanel;
  final bool showMembers;
  final bool showPins;
  final bool showThreads;
  final List<ConversationChannel> forumArchivedPosts;
  final bool isLoadingForumPosts;
  final Object? forumPostsError;
  final bool canLoadMoreForumPosts;
  final InboxSummary inboxSummary;
  final List<Member> typingMembers;
  final bool isSending;
  final bool isLoading;
  final Object? loadError;
  final bool canLoadOlder;
  final bool isLoadingOlder;
  final Object? olderLoadError;
  final VoidCallback onLoadOlder;
  final VoidCallback onRetry;
  final ValueChanged<String> onSelectChannel;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleMembers;
  final VoidCallback onTogglePins;
  final VoidCallback onToggleThreads;
  final VoidCallback onRefreshForumPosts;
  final VoidCallback onLoadMoreForumPosts;
  final ValueChanged<String> onLoadForumPostPreview;
  final CreateForumPostCallback onCreateForumPost;
  final VoidCallback onOpenInbox;
  final SendMessageCallback onSend;
  final CreatePollCallback onCreatePoll;
  final Future<bool> Function(List<String>) onSendStickers;
  final Future<bool> Function(ChatMessage, String) onEdit;
  final Future<void> Function(ChatMessage) onDelete;
  final Future<void> Function(ChatMessage, MessageReaction) onToggleReaction;
  final ReactionUsersLoader onLoadReactionUsers;
  final Future<void> Function(ChatMessage, String) onAddReaction;
  final Future<bool> Function(ChatMessage, String, int) onCreateThread;
  final Future<void> Function(ChatMessage) onTogglePin;
  final Future<bool> Function(ChatMessage) onEndPoll;
  final ForwardMessageCallback onForward;
  final Future<bool> Function(ChatMessage) onToggleSuppressEmbeds;
  final VoidCallback onTyping;
  final VoiceController voiceController;
  final VoiceMessageRecorder? voiceMessageRecorder;
  final SendVoiceMessageCallback onSendVoiceMessage;

  @override
  State<_ConversationPane> createState() => _ConversationPaneState();
}

class _ConversationPaneState extends State<_ConversationPane> {
  ChatMessage? _replyTo;

  @override
  void didUpdateWidget(covariant _ConversationPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) _replyTo = null;
  }

  @override
  Widget build(BuildContext context) {
    final showsMessages = _showsMessageTimeline(
      widget.channel,
      widget.voiceSurface,
    );
    final locked =
        widget.channel.isThread &&
        widget.channel.isArchived &&
        widget.channel.isLocked;
    final conversation = switch (widget.channel.kind) {
      ChannelKind.voice when !showsMessages => VoiceRoomView(
        guildId: widget.channel.spaceId,
        channelId: widget.channel.id,
        channelName: widget.channel.name,
        controller: widget.voiceController,
        members: widget.workspace.members,
        currentMemberId: widget.workspace.currentMemberId,
      ),
      ChannelKind.forum || ChannelKind.media => ForumChannelView(
        workspace: widget.workspace,
        channel: widget.channel,
        archivedPosts: widget.forumArchivedPosts,
        isLoading: widget.isLoadingForumPosts,
        error: widget.forumPostsError,
        canLoadMore: widget.canLoadMoreForumPosts,
        onRefresh: widget.onRefreshForumPosts,
        onLoadMore: widget.onLoadMoreForumPosts,
        onOpenPost: widget.onSelectChannel,
        onLoadPostPreview: widget.onLoadForumPostPreview,
        onCreatePost: widget.onCreateForumPost,
      ),
      ChannelKind.text || ChannelKind.voice => _buildTimeline(),
    };
    return Column(
      children: [
        ChatHeader(
          channel: widget.channel,
          channels: widget.channels,
          query: widget.query,
          showCompactPicker: widget.compact,
          showsMessages: showsMessages,
          voiceSurface: widget.voiceSurface,
          allowMemberPanel: widget.allowMemberPanel,
          allowThreadPanel: widget.allowThreadPanel,
          showMembers: widget.showMembers,
          showPins: widget.showPins,
          showThreads: widget.showThreads,
          inboxSummary: widget.inboxSummary,
          onSelectChannel: widget.onPickChannel,
          onSelectVoiceSurface: widget.onSelectVoiceSurface,
          onQueryChanged: widget.onQueryChanged,
          onToggleMembers: widget.onToggleMembers,
          onTogglePins: widget.onTogglePins,
          onToggleThreads: widget.onToggleThreads,
          onOpenInbox: widget.onOpenInbox,
        ),
        Expanded(child: conversation),
        if (showsMessages && !locked)
          TypingIndicator(members: widget.typingMembers),
        if (showsMessages && locked)
          const LockedThreadComposerNotice()
        else if (showsMessages)
          MessageComposer(
            channelId: widget.channel.id,
            channelName: widget.channel.name,
            channelIsVoice: widget.channel.kind == ChannelKind.voice,
            spaceName: widget.workspace.spaceById(widget.channel.spaceId).name,
            autocompleteCatalog: ComposerAutocompleteCatalog.fromWorkspace(
              widget.workspace,
              widget.channel,
            ),
            customEmojis: widget.workspace.emojisFor(widget.channel.spaceId),
            guildStickers: widget.workspace.stickersFor(widget.channel.spaceId),
            isSending: widget.isSending,
            replyTo: _replyTo,
            replyAuthor: _replyTo == null
                ? null
                : widget.workspace.memberOrNull(_replyTo!.authorId),
            onCancelReply: () => setState(() => _replyTo = null),
            onTyping: widget.onTyping,
            onCreatePoll: widget.onCreatePoll,
            onSendStickers: widget.onSendStickers,
            voiceMessageRecorder: widget.voiceMessageRecorder,
            onSendVoiceMessage: widget.onSendVoiceMessage,
            onSend:
                (
                  body,
                  attachments,
                  replyToMessageId,
                  suppressNotifications,
                ) async {
                  final sent = await widget.onSend(
                    body,
                    attachments,
                    replyToMessageId,
                    suppressNotifications,
                  );
                  if (mounted && sent) setState(() => _replyTo = null);
                  return sent;
                },
          ),
      ],
    );
  }

  /// One builder for every channel that owns a message timeline, so a voice
  /// channel's chat is literally the same widget tree as a text channel's
  /// rather than a second copy that can drift.
  Widget _buildTimeline() {
    if (widget.isLoading) return const ChannelLoadingView();
    if (widget.loadError != null) {
      return ChannelFailureView(onRetry: widget.onRetry);
    }
    return MessageList(
      workspace: widget.workspace,
      externalLinkLauncher: widget.externalLinkLauncher,
      attachmentDownloadService: widget.attachmentDownloadService,
      channel: widget.channel,
      query: widget.query,
      targetMessageId: widget.targetMessageId,
      onReply: (message) => setState(() => _replyTo = message),
      onEdit: widget.onEdit,
      onDelete: widget.onDelete,
      onToggleReaction: widget.onToggleReaction,
      onLoadReactionUsers: widget.onLoadReactionUsers,
      onAddReaction: widget.onAddReaction,
      onCreateThread: widget.onCreateThread,
      onTogglePin: widget.onTogglePin,
      onEndPoll: widget.onEndPoll,
      onForward: widget.onForward,
      onToggleSuppressEmbeds: widget.onToggleSuppressEmbeds,
      canLoadOlder: widget.canLoadOlder,
      isLoadingOlder: widget.isLoadingOlder,
      olderLoadError: widget.olderLoadError,
      onLoadOlder: widget.onLoadOlder,
      onSelectChannel: widget.onSelectChannel,
    );
  }
}
