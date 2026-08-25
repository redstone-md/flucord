import 'dart:async';

import 'package:flutter/material.dart';

import '../application/chat_controller.dart';
import '../application/composer_autocomplete_catalog.dart';
import '../application/direct_call_controller.dart';
import '../application/go_live_controller.dart';
import '../application/inbox_catalog.dart';
import '../application/report_flow_controller.dart';
import '../application/voice_channel_surface.dart';
import '../domain/channel_capabilities.dart';
import '../domain/chat_models.dart';
import '../domain/go_live_stream.dart';
import '../domain/moderation_report.dart';
import 'widgets/attachment_download_scope.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_scope.dart';
import 'widgets/direct_call_scope.dart';
import 'widgets/expression_favorites_scope.dart';
import 'widgets/external_link_launcher_scope.dart';
import 'widgets/forum_channel_view.dart';
import 'widgets/gif_picker_scope.dart';
import 'widgets/go_live_button.dart';
import 'widgets/go_live_display_dialog.dart';
import 'widgets/go_live_scope.dart';
import 'widgets/go_live_viewer.dart';
import 'widgets/stream_quality_scope.dart';
import 'widgets/message_component_scope.dart';
import 'widgets/message_composer.dart';
import 'widgets/message_list.dart';
import 'widgets/remote_camera_scope.dart';
import 'widgets/report_dialog.dart';
import 'widgets/slash_command_scope.dart';
import 'widgets/soundboard_picker.dart';
import 'widgets/soundboard_scope.dart';
import 'widgets/stage_controls.dart';
import 'widgets/stage_scope.dart';
import 'widgets/status_views.dart';
import 'widgets/stream_viewer_scope.dart';
import 'widgets/thread_browser_panel.dart';
import 'widgets/thread_membership_button.dart';
import 'widgets/thread_membership_scope.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/voice_message_recorder_scope.dart';
import 'widgets/voice_room_view.dart';
import 'widgets/voice_scope.dart';
import 'widgets/workspace_scope.dart';

/// The conversation surface for one channel: the header, the room or the
/// timeline it switches between, and the composer.
///
/// The pane's parameters are the channel, the workspace data it draws from,
/// and the layout facts that vary with the window. Every controller is
/// resolved from the scope modules above it (the `*_scope.dart` widgets), so
/// a new conversation feature is wired at the leaf widget it belongs to plus
/// the scope that publishes its controller, without any constructor between
/// here and the app changing.
///
/// What the host still owns stays an intent: navigation between channels, the
/// server search, and the inbox dialog.
class ConversationPane extends StatefulWidget {
  const ConversationPane({
    required this.workspace,
    required this.capabilities,
    required this.channel,
    required this.channels,
    required this.compact,
    required this.allowMemberPanel,
    required this.allowThreadPanel,
    required this.showMembers,
    required this.showPins,
    required this.showThreads,
    required this.onPickChannel,
    required this.onSelectChannel,
    this.onSubmitQuery,
    required this.onOpenInbox,
    super.key,
  });

  final ChatWorkspace workspace;

  /// What the account may do in [channel], resolved from its permissions.
  final ChannelCapabilities capabilities;
  final ConversationChannel channel;

  /// The channels the compact picker offers, already filtered to what this
  /// account can see.
  final List<ConversationChannel> channels;

  /// No channel sidebar fits, so the header's compact channel picker stands
  /// in for it.
  final bool compact;

  /// Whether the header may offer the member, thread and pin panels. These
  /// are layout facts: they depend on the window width and the space, not on
  /// the channel.
  final bool allowMemberPanel;
  final bool allowThreadPanel;
  final bool showMembers;
  final bool showPins;
  final bool showThreads;

  /// The compact channel picker stands in for the channel sidebar, so it keeps
  /// a voice channel's own surface. [onSelectChannel] is the message-shaped
  /// route (mentions, forum posts) and lands on the timeline instead.
  final ValueChanged<String> onPickChannel;
  final ValueChanged<String> onSelectChannel;

  /// Runs the text as a server search, or null when the session cannot search
  /// the server, which is how the header stops offering a query that could
  /// only ever fail.
  final ValueChanged<String>? onSubmitQuery;

  /// Opens the inbox, which belongs to the whole workspace rather than the
  /// open channel.
  final VoidCallback onOpenInbox;

  @override
  State<ConversationPane> createState() => _ConversationPaneState();
}

class _ConversationPaneState extends State<ConversationPane> {
  ChatMessage? _replyTo;

  @override
  void initState() {
    super.initState();
    _watchCall();
    _pointControllersAtChannel();
  }

  @override
  void didUpdateWidget(covariant ConversationPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id == widget.channel.id) return;
    _replyTo = null;
    _watchCall();
    _pointControllersAtChannel();
  }

  /// Subscribes the session to this channel's call (gateway opcode 13).
  ///
  /// Discord pushes `CALL_CREATE` only to subscribers, so a DM the client has
  /// never opened silently swallows every call placed in it. Opening the
  /// conversation is the moment the desktop client subscribes, and repeating
  /// it is harmless: the gateway keeps one subscription per channel.
  void _watchCall() {
    if (!widget.channel.isDirectMessage) return;
    DirectCallScope.maybeOf(context)?.watchChannel(widget.channel.id);
  }

  /// Points the channel-scoped controllers at the selected channel: thread
  /// membership, the stage, slash commands, and the soundboard.
  ///
  /// Deferred by a microtask because pointing them somewhere notifies
  /// synchronously, and this runs while the tree above is still building.
  void _pointControllersAtChannel() {
    scheduleMicrotask(() {
      if (!mounted) return;
      final context = this.context;
      final channel = widget.channel;
      // Only a thread has a membership to point at; every other channel gets
      // null, which clears the button rather than offering a control with
      // nothing to act on.
      ThreadMembershipScope.read(context).show(
        channel.isThread ? channel.id : null,
      );
      StageScope.read(context).show(
        channel.isStage ? channel.id : null,
        canModerate: widget.capabilities.moderateStage,
      );
      SlashCommandScope.read(context).show(
        channelId: channel.id,
        guildId: channel.spaceId.isEmpty ? null : channel.spaceId,
      );
      // A soundboard belongs to a server, and only a voice channel can play
      // one, so anything else clears the picker rather than offering sounds
      // with nowhere to send them.
      SoundboardScope.read(context).show(
        channel.kind == ChannelKind.voice ? channel.spaceId : null,
      );
    });
  }

  /// Asks which screen to share.
  ///
  /// The displays come from the encoder, not from a capture library. WebRTC's
  /// enumeration opens duplications of its own to build thumbnails with, and
  /// Windows refuses a second duplication of a display something already
  /// holds, which is what turned every share into "that display is no longer
  /// attached".
  Future<String?> _pickCaptureSource(BuildContext context) async {
    final displays = GoLiveScope.read(context).displays;
    // One screen, nothing to choose between.
    if (displays.length <= 1) return displays.firstOrNull?.sourceId;
    final picked = await showDialog<GoLiveDisplay>(
      context: context,
      builder: (_) => GoLiveDisplayDialog(displays: displays),
    );
    return picked?.sourceId;
  }

  /// Opens somebody's screen share, or closes the one already on screen.
  void _toggleWatch(String userId) {
    final viewer = StreamViewerScope.read(context);
    if (viewer.watching?.userId == userId) {
      unawaited(viewer.stop());
      return;
    }
    final spaceId = widget.channel.spaceId;
    final key = spaceId.isEmpty
        ? GoLiveStreamKey.call(channelId: widget.channel.id, userId: userId)
        : GoLiveStreamKey.guild(
            guildId: spaceId,
            channelId: widget.channel.id,
            userId: userId,
          );
    // Only the ask goes out here. Discord answers with an endpoint, and the
    // connection that answer opens is what feeds the viewer.
    unawaited(viewer.requestWatch(key));
  }

  @override
  Widget build(BuildContext context) {
    final calls = DirectCallScope.maybeOf(context);
    if (calls == null) return _buildPane(context, null);
    return ListenableBuilder(
      listenable: calls,
      builder: (context, _) => _buildPane(context, calls),
    );
  }

  Widget _buildPane(BuildContext context, DirectCallController? callController) {
    final chat = ChatScope.of(context);
    final workspaceController = WorkspaceScope.of(context);
    final channel = widget.channel;
    final inCall = callController?.activeCallChannelId == channel.id;
    final voiceSurface = workspaceController.voiceSurfaceOf(channel.id);
    final showsMessages = showsMessageTimeline(
      channel,
      voiceSurface,
      inCall: inCall,
    );
    final locked =
        channel.isThread && channel.isArchived && channel.isLocked;
    final viewer = StreamViewerScope.of(context);
    final cameras = RemoteCameraScope.of(context);
    final voice = VoiceScope.read(context);
    final goLive = GoLiveScope.read(context);
    final soundboard = SoundboardScope.read(context);
    final stage = StageScope.read(context);
    final threadMembership = ThreadMembershipScope.read(context);
    final conversation = inCall && !showsMessages
        ? VoiceRoomView(
            // A call has no guild; the DM pseudo-space still supplies avatars.
            guildId: null,
            spaceId: channel.spaceId,
            channelId: channel.id,
            channelName: channel.name,
            controller: voice,
            cameraFrameFor: cameras.frameFor,
            members: widget.workspace.members,
            currentMemberId: widget.workspace.currentMemberId,
          )
        : switch (channel.kind) {
            ChannelKind.voice when !showsMessages => VoiceRoomView(
              // Watching is asked for, never assumed: the pictures cross a
              // second connection Discord only opens when told to, and a room
              // that dialled every share in it would be paying for streams
              // nobody is looking at.
              onWatchStream: _toggleWatch,
              // What is on the stage, which is only a stream that is actually
              // arriving. Keying this on the ask meant a request Discord never
              // answered hid the participant grid for the rest of the call.
              watchedUserId: viewer.watching?.userId,
              pendingWatchUserId: viewer.requested?.userId,
              // Whoever is being watched takes the stage; the participant grid
              // is what the room shows when nobody is.
              streamViewer: ListenableBuilder(
                listenable: viewer,
                builder: (_, _) => viewer.watching == null
                    ? const SizedBox.shrink()
                    : GoLiveViewer(
                        frames: viewer.frames,
                        label: viewer.watching!.userId,
                      ),
              ),
              goLive: ListenableBuilder(
                listenable: goLive,
                builder: (_, _) => GoLiveButton(
                  controller: goLive,
                  channelId: channel.id,
                  quality: StreamQualityScope.maybeOf(context),
                  pickSource: () => _pickCaptureSource(context),
                  guildId: channel.spaceId.isEmpty
                      ? null
                      : channel.spaceId,
                ),
              ),
              soundboard: ListenableBuilder(
                listenable: soundboard,
                builder: (_, _) => SoundboardButton(
                  controller: soundboard,
                  channelId: channel.id,
                ),
              ),
              stageControls: channel.isStage
                  ? ListenableBuilder(
                      listenable: stage,
                      builder: (_, _) => StageControls(controller: stage),
                    )
                  : null,
              guildId: channel.spaceId,
              channelId: channel.id,
              channelName: channel.name,
              controller: voice,
              cameraFrameFor: cameras.frameFor,
              members: widget.workspace.members,
              currentMemberId: widget.workspace.currentMemberId,
            ),
            ChannelKind.forum || ChannelKind.media => ForumChannelView(
              workspace: widget.workspace,
              channel: channel,
              archivedPosts: chat.archivedThreadsFor(channel.id),
              isLoading: chat.isLoadingArchivedThreads(channel.id),
              error: chat.archivedThreadsError(channel.id),
              canLoadMore: chat.canLoadMoreArchivedThreads(channel.id),
              onRefresh: () => unawaited(
                chat.loadArchivedThreads(channel.id, refresh: true),
              ),
              onLoadMore: () =>
                  unawaited(chat.loadArchivedThreads(channel.id)),
              onOpenPost: widget.onSelectChannel,
              onLoadPostPreview: (postId) =>
                  unawaited(chat.loadForumPostPreview(postId)),
              onCreatePost: (name, content, attachments, duration, tagIds) async {
                final thread = await chat.createForumPost(
                  channelId: channel.id,
                  name: name,
                  content: content,
                  autoArchiveDurationMinutes: duration,
                  attachments: attachments,
                  appliedTagIds: tagIds,
                );
                if (thread == null) return false;
                widget.onSelectChannel(thread.id);
                return true;
              },
            ),
            ChannelKind.text || ChannelKind.voice => _buildTimeline(context),
          };
    return Column(
      children: [
        ChatHeader(
          channel: channel,
          // Only a thread has a membership to join; every other channel gets
          // nothing rather than a control that would have nothing to act on.
          threadMembership: channel.isThread
              ? ListenableBuilder(
                  listenable: threadMembership,
                  builder: (_, _) => ThreadMembershipButton(
                    controller: threadMembership,
                  ),
                )
              : null,
          channels: widget.channels,
          query: workspaceController.query,
          showCompactPicker: widget.compact,
          showsMessages: showsMessages,
          voiceSurface: voiceSurface,
          showVoiceSurfaces: hasVoiceSurfaces(channel, inCall: inCall),
          isInCall: inCall,
          callLabel: _callLabel(callController, inCall),
          onToggleCall: _callToggle(callController, inCall),
          allowMemberPanel: widget.allowMemberPanel,
          allowThreadPanel: widget.allowThreadPanel,
          showMembers: widget.showMembers,
          showPins: widget.showPins,
          showThreads: widget.showThreads,
          inboxSummary: InboxSummary.fromWorkspace(widget.workspace),
          onSelectChannel: widget.onPickChannel,
          onSelectVoiceSurface: (surface) =>
              workspaceController.selectVoiceSurface(channel.id, surface),
          onQueryChanged: workspaceController.setQuery,
          onSubmitQuery: widget.onSubmitQuery,
          onToggleMembers: workspaceController.toggleMembers,
          onTogglePins: () {
            workspaceController.togglePins();
            if (workspaceController.showPins) {
              unawaited(chat.loadPinnedMessages(channel.id));
            }
          },
          onToggleThreads: () {
            workspaceController.toggleThreads();
            final threadParentId = channel.threadParentId;
            if (workspaceController.showThreads && threadParentId != null) {
              unawaited(chat.loadArchivedThreads(threadParentId));
            }
          },
          onOpenInbox: widget.onOpenInbox,
        ),
        Expanded(child: conversation),
        if (showsMessages && !locked)
          TypingIndicator(members: chat.typingMembersFor(channel.id)),
        if (showsMessages && locked)
          const LockedThreadComposerNotice()
        else if (showsMessages && !widget.capabilities.sendMessages)
          const ReadOnlyChannelNotice()
        else if (showsMessages)
          MessageComposer(
            gifPicker: GifPickerScope.read(context),
            expressionFavorites: ExpressionFavoritesScope.read(context),
            slashCommands: SlashCommandScope.read(context),
            canAttachFiles: widget.capabilities.attachFiles,
            channelId: channel.id,
            channelName: channel.name,
            channelIsVoice: channel.kind == ChannelKind.voice,
            spaceName: widget.workspace.spaceById(channel.spaceId).name,
            autocompleteCatalog: ComposerAutocompleteCatalog.fromWorkspace(
              widget.workspace,
              channel,
            ),
            onSearchMembers: (query) => chat.searchGuildMembers(
              spaceId: channel.spaceId,
              query: query,
            ),
            customEmojis: widget.workspace.emojisFor(channel.spaceId),
            guildStickers: widget.workspace.stickersFor(channel.spaceId),
            isSending: chat.isSending,
            replyTo: _replyTo,
            replyAuthor: _replyTo == null
                ? null
                : widget.workspace.memberOrNull(_replyTo!.authorId),
            onCancelReply: () => setState(() => _replyTo = null),
            onTyping: () => chat.startTyping(channel.id),
            onCreatePoll: (poll) =>
                chat.createPoll(channelId: channel.id, poll: poll),
            onSendStickers: (stickerIds) => chat.sendStickers(
              channelId: channel.id,
              stickerIds: stickerIds,
            ),
            voiceMessageRecorder: VoiceMessageRecorderScope.maybeOf(context),
            onSendVoiceMessage: (voiceMessage) => chat.sendVoiceMessage(
              channelId: channel.id,
              voiceMessage: voiceMessage,
            ),
            onSend:
                (
                  body,
                  attachments,
                  replyToMessageId,
                  suppressNotifications,
                ) async {
                  final sent = await chat.sendMessage(
                    channelId: channel.id,
                    body: body,
                    attachments: attachments,
                    replyToMessageId: replyToMessageId,
                    suppressNotifications: suppressNotifications,
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
  /// rather than a second copy that could drift.
  Widget _buildTimeline(BuildContext context) {
    final chat = ChatScope.of(context);
    final channel = widget.channel;
    if (chat.isChannelLoading(channel.id)) {
      return const ChannelLoadingView();
    }
    if (chat.channelError(channel.id) != null) {
      return ChannelFailureView(
        onRetry: () => chat.openChannel(channel.id, refresh: true),
      );
    }
    final workspaceController = WorkspaceScope.of(context);
    return MessageList(
      expressionFavorites: ExpressionFavoritesScope.read(context),
      componentController: MessageComponentScope.read(context),
      applicationCommands: SlashCommandScope.read(context),
      workspace: widget.workspace,
      capabilities: widget.capabilities,
      externalLinkLauncher: ExternalLinkLauncherScope.maybeOf(context)!,
      attachmentDownloadService: AttachmentDownloadScope.maybeOf(context)!,
      channel: channel,
      query: workspaceController.query,
      targetMessageId: workspaceController.targetMessageId,
      onReply: (message) => setState(() => _replyTo = message),
      onEdit: chat.editMessage,
      onDelete: chat.deleteMessage,
      onToggleReaction: chat.toggleReaction,
      onLoadReactionUsers: chat.loadReactionUsers,
      onAddReaction: chat.addReaction,
      onCreateThread: (message, name, duration) async {
        final thread = await chat.createThreadFromMessage(
          message,
          name: name,
          autoArchiveDurationMinutes: duration,
        );
        if (thread == null) return false;
        widget.onSelectChannel(thread.id);
        return true;
      },
      onTogglePin: chat.togglePin,
      onResolveAlert: chat.resolveAutoModAlert,
      onReport: (message) => unawaited(_reportMessage(context, message)),
      onEndPoll: chat.endPoll,
      onForward: (message, targetChannelId) async {
        final forwarded = await chat.forwardMessage(message, targetChannelId);
        if (!forwarded) return false;
        widget.onSelectChannel(targetChannelId);
        return true;
      },
      onToggleSuppressEmbeds: chat.toggleSuppressEmbeds,
      canLoadOlder: chat.canLoadOlderMessages(channel.id),
      isLoadingOlder: chat.isLoadingOlderMessages(channel.id),
      olderLoadError: chat.olderMessagesError(channel.id),
      onLoadOlder: () => unawaited(chat.loadOlderMessages(channel.id)),
      onSelectChannel: widget.onSelectChannel,
    );
  }

  /// Opens the in-app report flow for one message.
  ///
  /// A first DM from somebody not yet spoken to has its own report type, and
  /// its own menu, so the target says which it is rather than the surface
  /// guessing after the menu comes back.
  Future<void> _reportMessage(BuildContext context, ChatMessage message) async {
    final chat = ChatScope.read(context);
    final repository = chat.moderation;
    if (repository == null) return;
    final controller = ReportFlowController(
      repository,
      target: MessageReportTarget(
        channelId: message.channelId,
        messageId: message.id,
        isFirstDirectMessage: _isFirstDirectMessage(
          widget.workspace,
          message,
        ),
      ),
    );
    try {
      await showReportDialog(context: context, controller: controller);
    } finally {
      controller.dispose();
    }
  }

  /// Whether this is the opening message of a DM from somebody the account
  /// has not written to. Discord treats that case separately because it is
  /// the one where the reporter has no history to judge the sender by.
  bool _isFirstDirectMessage(ChatWorkspace workspace, ChatMessage message) {
    final channel = workspace.channels
        .where((candidate) => candidate.id == message.channelId)
        .firstOrNull;
    if (channel == null || channel.spaceId != CommunitySpace.directMessagesId) {
      return false;
    }
    final inChannel = [
      for (final candidate in workspace.messages)
        if (candidate.channelId == message.channelId) candidate,
    ];
    return inChannel.length == 1 &&
        inChannel.single.id == message.id &&
        message.authorId != workspace.currentMemberId;
  }
}
