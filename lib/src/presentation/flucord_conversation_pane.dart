part of 'flucord_shell.dart';

/// A voice channel only behaves like a text channel while its chat surface is
/// the one on screen: the room has no timeline to search, pin, or type into.
/// Forum and media channels never qualify — their messages live in posts.
///
/// A DM in a call earns the same two surfaces for the same reason. The call is
/// a room hanging off a channel that also has a timeline, which is exactly the
/// shape a voice channel has, so it reuses the switch rather than inventing a
/// second way to say "show me the room".
bool _showsMessageTimeline(
  ConversationChannel channel,
  VoiceChannelSurface voiceSurface, {
  bool inCall = false,
}) =>
    channel.hasMessageTimeline &&
    ((channel.kind != ChannelKind.voice && !inCall) ||
        voiceSurface == VoiceChannelSurface.chat);

/// Whether [channel] shows the room-or-chat switch at all.
bool _hasVoiceSurfaces(ConversationChannel channel, {required bool inCall}) =>
    channel.kind == ChannelKind.voice || inCall;

class _ConversationPane extends StatefulWidget {
  const _ConversationPane({
    required this.workspace,
    required this.capabilities,
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
    required this.onSubmitQuery,
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
    this.onResolveAlert,
    required this.onEndPoll,
    required this.onForward,
    required this.onToggleSuppressEmbeds,
    required this.onTyping,
    required this.voiceController,
    required this.threadMembershipController,
    required this.stageController,
    required this.soundboardController,
    required this.goLiveController,
    required this.streamViewerController,
    required this.gifPickerController,
    required this.slashCommandController,
    required this.messageComponentController,
    required this.voiceMessageRecorder,
    required this.onSendVoiceMessage,
    this.directCallController,
  });

  final ChatWorkspace workspace;

  /// What the account may do in [channel], resolved from its permissions.
  final ChannelCapabilities capabilities;
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

  /// Null when the session cannot search the server, which is how the header
  /// stops offering a query that could only ever fail.
  final ValueChanged<String>? onSubmitQuery;
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
  final Future<void> Function(ChatMessage, AutoModAlertAction)? onResolveAlert;
  final Future<bool> Function(ChatMessage) onEndPoll;
  final ForwardMessageCallback onForward;
  final Future<bool> Function(ChatMessage) onToggleSuppressEmbeds;
  final VoidCallback onTyping;
  final VoiceController voiceController;
  final ThreadMembershipController threadMembershipController;
  final StageController stageController;
  final SoundboardController soundboardController;
  final GoLiveController goLiveController;
  final StreamViewerController streamViewerController;
  final GifPickerController gifPickerController;
  final SlashCommandController slashCommandController;
  final MessageComponentController messageComponentController;
  final VoiceMessageRecorder? voiceMessageRecorder;
  final SendVoiceMessageCallback onSendVoiceMessage;

  /// Absent in hosts with no call plane — a demo workspace or a bot session —
  /// which is also how the call affordances stay off rather than failing.
  final DirectCallController? directCallController;

  @override
  State<_ConversationPane> createState() => _ConversationPaneState();
}

class _ConversationPaneState extends State<_ConversationPane> {
  ChatMessage? _replyTo;

  @override
  void initState() {
    super.initState();
    _watchCall();
    _watchThreadMembership();
  }

  @override
  void didUpdateWidget(covariant _ConversationPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id == widget.channel.id) return;
    _replyTo = null;
    _watchCall();
    _watchThreadMembership();
  }

  /// Points the membership controller at this channel, when it is a thread.
  ///
  /// Deferred by a microtask because pointing it somewhere notifies
  /// synchronously, and this runs while the listener above is building.
  void _watchThreadMembership() {
    final threadId = widget.channel.isThread ? widget.channel.id : null;
    final stageId = widget.channel.isStage ? widget.channel.id : null;
    scheduleMicrotask(() {
      if (!mounted) return;
      widget.threadMembershipController.show(threadId);
      widget.stageController.show(
        stageId,
        canModerate: widget.capabilities.moderateStage,
      );
      // A soundboard belongs to a server, and only a voice channel can play
      // one, so anything else clears the picker rather than offering sounds
      // with nowhere to send them.
      widget.slashCommandController.show(
        channelId: widget.channel.id,
        guildId: widget.channel.spaceId.isEmpty ? null : widget.channel.spaceId,
      );
      widget.soundboardController.show(
        widget.channel.kind == ChannelKind.voice
            ? widget.channel.spaceId
            : null,
      );
    });
  }

  /// Subscribes the session to this channel's call (gateway opcode 13).
  ///
  /// Discord pushes `CALL_CREATE` only to subscribers, so a DM the client has
  /// never opened silently swallows every call placed in it. Opening the
  /// conversation is the moment the desktop client subscribes, and repeating it
  /// is harmless — the gateway keeps one subscription per channel.
  void _watchCall() {
    if (!widget.channel.isDirectMessage) return;
    widget.directCallController?.watchChannel(widget.channel.id);
  }

  /// The call state is read on every build, so the pane has to be rebuilt when
  /// it moves — joining a call is what swaps the timeline for the room.
  @override
  Widget build(BuildContext context) {
    final controller = widget.directCallController;
    if (controller == null) return _buildPane(context, null);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildPane(context, controller),
    );
  }

  Widget _buildPane(
    BuildContext context,
    DirectCallController? callController,
  ) {
    final inCall = callController?.activeCallChannelId == widget.channel.id;
    final showsMessages = _showsMessageTimeline(
      widget.channel,
      widget.voiceSurface,
      inCall: inCall,
    );
    final locked =
        widget.channel.isThread &&
        widget.channel.isArchived &&
        widget.channel.isLocked;
    final conversation = inCall && !showsMessages
        ? VoiceRoomView(
            // A call has no guild; the DM pseudo-space still supplies avatars.
            guildId: null,
            spaceId: widget.channel.spaceId,
            channelId: widget.channel.id,
            channelName: widget.channel.name,
            controller: widget.voiceController,
            members: widget.workspace.members,
            currentMemberId: widget.workspace.currentMemberId,
          )
        : switch (widget.channel.kind) {
            ChannelKind.voice when !showsMessages => VoiceRoomView(
              // Whoever is being watched takes the stage; the participant grid
              // is what the room shows when nobody is.
              streamViewer: ListenableBuilder(
                listenable: widget.streamViewerController,
                builder: (_, _) =>
                    widget.streamViewerController.watching == null
                    ? const SizedBox.shrink()
                    : GoLiveViewer(
                        frames: widget.streamViewerController.frames,
                        label: widget.streamViewerController.watching!.userId,
                      ),
              ),
              goLive: ListenableBuilder(
                listenable: widget.goLiveController,
                builder: (_, _) => GoLiveButton(
                  controller: widget.goLiveController,
                  channelId: widget.channel.id,
                  guildId: widget.channel.spaceId.isEmpty
                      ? null
                      : widget.channel.spaceId,
                ),
              ),
              soundboard: ListenableBuilder(
                listenable: widget.soundboardController,
                builder: (_, _) => SoundboardButton(
                  controller: widget.soundboardController,
                  channelId: widget.channel.id,
                ),
              ),
              stageControls: widget.channel.isStage
                  ? ListenableBuilder(
                      listenable: widget.stageController,
                      builder: (_, _) =>
                          StageControls(controller: widget.stageController),
                    )
                  : null,
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
          // Only a thread has a membership to join; every other channel gets
          // nothing rather than a control that would have nothing to act on.
          threadMembership: widget.channel.isThread
              ? ListenableBuilder(
                  listenable: widget.threadMembershipController,
                  builder: (_, _) => ThreadMembershipButton(
                    controller: widget.threadMembershipController,
                  ),
                )
              : null,
          channels: widget.channels,
          query: widget.query,
          showCompactPicker: widget.compact,
          showsMessages: showsMessages,
          voiceSurface: widget.voiceSurface,
          showVoiceSurfaces: _hasVoiceSurfaces(widget.channel, inCall: inCall),
          isInCall: inCall,
          callLabel: _callLabel(callController, inCall),
          onToggleCall: _callToggle(callController, inCall),
          allowMemberPanel: widget.allowMemberPanel,
          allowThreadPanel: widget.allowThreadPanel,
          showMembers: widget.showMembers,
          showPins: widget.showPins,
          showThreads: widget.showThreads,
          inboxSummary: widget.inboxSummary,
          onSelectChannel: widget.onPickChannel,
          onSelectVoiceSurface: widget.onSelectVoiceSurface,
          onQueryChanged: widget.onQueryChanged,
          onSubmitQuery: widget.onSubmitQuery,
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
        else if (showsMessages && !widget.capabilities.sendMessages)
          const ReadOnlyChannelNotice()
        else if (showsMessages)
          MessageComposer(
            gifPicker: widget.gifPickerController,
            slashCommands: widget.slashCommandController,
            canAttachFiles: widget.capabilities.attachFiles,
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

  /// The header's call button, or null when this channel cannot be called.
  ///
  /// Only a private channel can: guild voice is joined from the sidebar, and a
  /// transport with no call plane hands out no controller at all.
  VoidCallback? _callToggle(DirectCallController? controller, bool inCall) {
    if (controller == null || !controller.supportsCalls) return null;
    if (!widget.channel.isDirectMessage && !inCall) return null;
    if (controller.isBusy) return null;
    if (inCall) return () => unawaited(controller.hangUp());
    // A call that is already running is joined, not placed: the people in it
    // are there, and ringing the ones who declined would only be noise.
    final ongoing = controller.callFor(widget.channel.id);
    return ongoing != null && !ongoing.unavailable
        ? () => unawaited(controller.joinOngoingCall(widget.channel.id))
        : () => unawaited(controller.placeCall(widget.channel.id));
  }

  /// What the header's call button should say.
  String? _callLabel(DirectCallController? controller, bool inCall) {
    if (controller == null) return null;
    if (inCall) return 'Leave call';
    if (controller.isRinging(widget.channel.id)) return 'Ringing…';
    return controller.callFor(widget.channel.id) == null
        ? 'Start call'
        : 'Join call';
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
      componentController: widget.messageComponentController,
      applicationCommands: widget.slashCommandController,
      workspace: widget.workspace,
      capabilities: widget.capabilities,
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
      onResolveAlert: widget.onResolveAlert,
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
