import 'dart:async';

import 'package:flutter/material.dart';

import '../application/chat_controller.dart';
import '../application/composer_autocomplete_catalog.dart';
import '../application/direct_call_controller.dart';
import '../application/inbox_catalog.dart';
import '../application/report_flow_controller.dart';
import '../application/send_failure.dart';
import '../application/voice_channel_surface.dart';
import '../application/stream_viewer_controller.dart';
import '../domain/account_entitlements.dart';
import '../domain/channel_capabilities.dart';
import '../domain/chat_models.dart';
import '../domain/conversation_summary.dart';
import '../domain/go_live_stream.dart';
import '../domain/moderation_report.dart';
import 'widgets/account_entitlements_scope.dart';
import 'widgets/attachment_download_scope.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_scope.dart';
import 'widgets/conversation_summaries.dart';
import 'widgets/direct_message_views.dart';
import 'widgets/direct_call_scope.dart';
import 'widgets/emoji_picker.dart';
import 'widgets/expression_favorites_scope.dart';
import 'widgets/external_link_launcher_scope.dart';
import 'widgets/forum_channel_view.dart';
import 'widgets/gif_picker_scope.dart';
import 'widgets/go_live_button.dart';
import 'widgets/go_live_display_dialog.dart';
import '../application/workspace_controller.dart';
import 'widgets/cached_subtree.dart';
import 'widgets/go_live_scope.dart';
import 'widgets/go_live_viewer.dart';
import 'widgets/stream_quality_scope.dart';
import 'widgets/message_component_scope.dart';
import 'widgets/message_composer.dart';
import 'widgets/message_list.dart';
import 'widgets/remote_camera_scope.dart';
import 'widgets/report_dialog.dart';
import 'widgets/profile_card_route.dart';
import 'widgets/self_video_scope.dart';
import 'widgets/slash_command_scope.dart';
import 'widgets/soundboard_picker.dart';
import 'widgets/soundboard_scope.dart';
import 'widgets/sticker_picker.dart';
import 'widgets/stage_controls.dart';
import 'widgets/stage_scope.dart';
import 'widgets/status_views.dart';
import 'widgets/room_focus_scope.dart';
import 'widgets/stream_viewer_scope.dart';
import 'widgets/thread_browser_panel.dart';
import 'widgets/thread_membership_button.dart';
import 'widgets/thread_membership_scope.dart';
import 'widgets/timeline_dependencies.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/voice_message_recorder_scope.dart';
import 'widgets/participant_menu.dart';
import 'widgets/voice_room_view.dart';
import 'widgets/voice_room_status.dart';
import 'widgets/voice_scope.dart';
import 'widgets/voice_stream_controls.dart';
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
    this.onOpenMemberProfile,
    this.onMessageMember,
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

  /// Opens the profile of a message's author beside their name.
  final OpenProfileCard? onOpenMemberProfile;

  /// Opens the direct message with a member, from the participant menu.
  final ValueChanged<String>? onMessageMember;

  @override
  State<ConversationPane> createState() => ConversationPaneState();
}

/// Public so the shell's keyboard map can reach the open conversation through a
/// global key, as a form reaches its `FormState`.
class ConversationPaneState extends State<ConversationPane> {
  /// Holds a send failure's note clear of the composer, even with four lines
  /// of text in it. A note at the window's edge would cover the restored text
  /// and the Send button the user needs to try again.
  static const _aboveComposer = EdgeInsets.fromLTRB(16, 0, 16, 140);

  final _composerKey = GlobalKey<MessageComposerState>();
  final _timelineKey = GlobalKey<MessageListState>();

  static String _composerHintPrefix(ConversationChannel channel) {
    if (channel.soleRecipientId != null) return '@';
    final hasNoHash =
        channel.kind == ChannelKind.voice ||
        channel.spaceId == CommunitySpace.directMessagesId;
    return hasNoHash ? '' : '#';
  }

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
    _watchCall();
    _pointControllersAtChannel();
  }

  /// Puts the cursor in the composer, if this channel has one.
  void focusComposer() => _composerKey.currentState?.focus();

  /// Types [text] into the composer and focuses it. Answers false when this
  /// channel has no composer to type in.
  bool typeInComposer(String text) =>
      _composerKey.currentState?.typeText(text) ?? false;

  /// Puts a mention of [userId] in the composer. A Room has no composer, so
  /// the channel's chat is opened first; a channel with no chat at all
  /// takes nothing.
  void mention(String userId) {
    final text = '<@$userId> ';
    if (typeInComposer(text)) return;
    final channel = widget.channel;
    if (!channel.hasMessageTimeline) return;
    WorkspaceScope.of(
      context,
    ).selectVoiceSurface(channel.id, VoiceChannelSurface.chat);
    // The composer is there once the chat has been drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) typeInComposer(text);
    });
  }

  /// Esc takes one step back: a reply being written goes first. With none, the
  /// reader is done here, so the channel is read and the list goes to the end.
  /// A room has no timeline to be done with.
  void handleEscape() {
    final chat = ChatScope.read(context);
    final channelId = widget.channel.id;
    if (chat.drafts.read(channelId).replyTo != null) {
      _setReply(chat, null);
      return;
    }
    final timeline = _timelineKey.currentState;
    if (timeline == null) return;
    chat.markChannelRead(channelId);
    timeline.jumpToPresent();
  }

  /// Moves the timeline by most of a screen, if this channel has one.
  void scrollTimelinePage(int direction) =>
      _timelineKey.currentState?.scrollPage(direction);

  /// Sets who the open channel's draft answers.
  void _setReply(ChatController chat, ChatMessage? message) {
    final channelId = widget.channel.id;
    setState(() {
      chat.drafts.write(
        channelId,
        chat.drafts.read(channelId).withReply(message),
      );
    });
  }

  /// When slowmode releases this account's next send, or null while nothing
  /// is holding it back. Slowmode binds the sender, not the channel: the
  /// clock starts at this account's own last send.
  DateTime? _slowmodeUntil(ChatController chat) {
    final seconds = widget.channel.rateLimitPerUser;
    final lastSentAt = chat.lastSentAt(widget.channel.id);
    if (seconds == 0 ||
        lastSentAt == null ||
        widget.capabilities.bypassesSlowmode) {
      return null;
    }
    final until = lastSentAt.add(Duration(seconds: seconds));
    return until.isBefore(DateTime.now()) ? null : until;
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
      ThreadMembershipScope.read(
        context,
      ).show(channel.isThread ? channel.id : null);
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
      SoundboardScope.read(
        context,
      ).show(channel.kind == ChannelKind.voice ? channel.spaceId : null);
    });
  }

  /// Opens somebody's screen share, or closes the one already on screen.
  ///
  /// An ask that is still waiting counts as open: its control has read
  /// "Stop watching" since the ask went out, so pressing it has to withdraw
  /// that ask rather than send a second one.
  void _toggleWatch(String userId) {
    final viewer = StreamViewerScope.read(context);
    unawaited(_openOrClose(viewer, widget.channel.streamKeyFor(userId)));
  }

  Future<void> _openOrClose(
    StreamViewerController viewer,
    GoLiveStreamKey key,
  ) async {
    if (viewer.isOpen(key)) {
      await viewer.stop(key);
      return;
    }
    // Only the ask goes out here. Discord answers with an endpoint, and the
    // connection that answer opens is what feeds the viewer. Asking is
    // wanting to look: the stream takes the stage as soon as it arrives.
    if (mounted) RoomFocusScope.read(context).focus(key.userId);
    if (await viewer.requestWatch(key)) return;
    if (!mounted || viewer.refused != key) return;
    // Turned down for want of room, which is a limit of ours and not
    // Discord's: a control that does nothing when pressed reads as broken.
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'You can watch up to $maxWatchedStreams streams at once. Stop one first.',
        ),
      ),
    );
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

  Widget _buildPane(
    BuildContext context,
    DirectCallController? callController,
  ) {
    final chat = ChatScope.of(context);
    final workspaceController = WorkspaceScope.of(context);
    final channel = widget.channel;
    final replyTo = chat.drafts.read(channel.id).replyTo;
    final inCall = callController?.activeCallChannelId == channel.id;
    final voiceSurface = workspaceController.voiceSurfaceOf(channel.id);
    final showsMessages = showsMessageTimeline(
      channel,
      voiceSurface,
      inCall: inCall,
    );
    final locked = channel.isThread && channel.isArchived && channel.isLocked;
    // Read and not watched: the viewer announces every decoded unit, and
    // several streams at once announce one each. The room below is what
    // rebuilds, and the timeline beside it has no business being laid out
    // thirty times a second per stream.
    final viewer = StreamViewerScope.read(context);
    final cameras = RemoteCameraScope.of(context);
    final voice = VoiceScope.read(context);
    final goLive = GoLiveScope.read(context);
    final camera = SelfVideoScope.read(context);
    final soundboard = SoundboardScope.read(context);
    final stage = StageScope.read(context);
    final threadMembership = ThreadMembershipScope.read(context);
    // A call is a room without a guild, and a stream is addressed by the room
    // rather than by the server, so both rooms carry one and the same block of
    // controls rather than two copies that could drift. Built on demand and
    // not up here: attaching the Go Live control binds it to the transport,
    // which a channel with no room on screen has no business doing.
    // The focused participant's stream takes the stage while it is arriving;
    // otherwise the room draws their tile large, and null is how it is told.
    // Asked-for is not on the stage: an endpoint that never comes must not
    // take the room away.
    final focus = RoomFocusScope.of(context);
    Widget? streamViewer() {
      final userId = focus.userId;
      if (userId == null) return null;
      final key = channel.streamKeyFor(userId);
      if (!viewer.isWatching(key)) return null;
      return GoLiveViewer(
        textures: viewer.texturesFor(key),
        label: userId,
        error: viewer.errorFor(key),
      );
    }

    Widget goLiveControl() => ListenableBuilder(
      listenable: goLive,
      builder: (_, _) => GoLiveButton(
        controller: goLive,
        channelId: channel.id,
        quality: StreamQualityScope.maybeOf(context),
        pickSource: () => GoLiveDisplayDialog.pick(context, goLive.displays),
        guildId: channel.guildId,
      ),
    );

    // Null while there is no share. Go Live is the only authority: the roster
    // reports a stream only once Discord echoes one back.
    VoidCallback? stopShare() =>
        goLive.isSharing ? () => unawaited(goLive.stop()) : null;

    // The sender's own picture stays on their tile in the grid, never on the
    // stage: somebody sharing is watching the room, not themselves. Its
    // pictures are the encoder's, decoded locally (ADR-0001).
    VoiceSelfPreview? selfPreview() {
      if (!goLive.isSharing) return null;
      final key = goLive.streamKey;
      if (key == null || key.channelId != channel.id) return null;
      return VoiceSelfPreview(
        textures: goLive.previewTextures,
        error: goLive.previewError,
      );
    }

    // What the tiles know about the streams this client is holding: which
    // ones are open, and how to open or close one. One value rather than
    // four arguments because the mark is asked of each tile now.
    VoiceStreamControls streamControls() => VoiceStreamControls(
      isOpen: (userId) => viewer.isOpen(widget.channel.streamKeyFor(userId)),
      hasFailed: (userId) =>
          viewer.errorFor(widget.channel.streamKeyFor(userId)) != null,
      onWatch: _toggleWatch,
      onStopShare: stopShare(),
      selfPreview: selfPreview(),
    );

    // What a right click on a participant opens, the same on every tile.
    ParticipantMenu participantMenu() => ParticipantMenu(
      voice: voice,
      currentMemberId: widget.workspace.currentMemberId,
      actions: ParticipantMenuActions(
        onOpenProfile: widget.onOpenMemberProfile,
        onMessage: widget.onMessageMember,
        onMention: mention,
      ),
    );

    Widget room() => inCall && !showsMessages
        ? VoiceRoomView(
            // A call has no guild; the DM pseudo-space still supplies avatars.
            guildId: null,
            spaceId: channel.spaceId,
            participantMenu: participantMenu(),
            // Watching is asked for, never assumed: the pictures cross a
            // second connection Discord only opens when told to, and a room
            // that dialled every stream in it would be paying for pictures
            // nobody is looking at.
            streams: streamControls(),
            // What is on the stage, which is only a stream that is actually
            // arriving. Keying this on the ask meant a request Discord never
            // answered hid the participant grid for the rest of the call.
            streamViewer: streamViewer(),
            focusedUserId: focus.userId,
            onTapParticipant: focus.toggle,
            onClearFocus: focus.clear,
            goLive: goLiveControl(),
            camera: camera,
            channelId: channel.id,
            channelName: channel.name,
            controller: voice,
            cameraTextureFor: cameras.textureFor,
            members: widget.workspace.members,
            currentMemberId: widget.workspace.currentMemberId,
          )
        : switch (channel.kind) {
            ChannelKind.voice when !showsMessages => VoiceRoomView(
              streams: streamControls(),
              streamViewer: streamViewer(),
              participantMenu: participantMenu(),
              focusedUserId: focus.userId,
              onTapParticipant: focus.toggle,
              onClearFocus: focus.clear,
              goLive: goLiveControl(),
              camera: camera,
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
              guildId: channel.guildId,
              channelId: channel.id,
              channelName: channel.name,
              controller: voice,
              cameraTextureFor: cameras.textureFor,
              members: widget.workspace.members,
              currentMemberId: widget.workspace.currentMemberId,
            ),
            ChannelKind.forum || ChannelKind.media => ForumChannelView(
              workspace: widget.workspace,
              channel: channel,
              posts: chat.threadsFor(channel.id),
              isLoading: chat.isLoadingThreads(channel.id),
              error: chat.threadsError(channel.id),
              canLoadMore: chat.canLoadMoreThreads(channel.id),
              onRefresh: () =>
                  unawaited(chat.loadThreads(channel.id, refresh: true)),
              onLoadMore: () => unawaited(chat.loadThreads(channel.id)),
              onFilterTags: (tagIds) =>
                  unawaited(chat.loadThreads(channel.id, tagIds: tagIds)),
              onOpenPost: widget.onSelectChannel,
              onLoadPostPreview: (postId) =>
                  unawaited(chat.loadForumPostPreview(postId)),
              onCreatePost:
                  (name, content, attachments, duration, tagIds) async {
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

    // Only the room is rebuilt when this account's own share starts or stops,
    // or when a stream opens, closes or hands the stage to another: a text
    // channel has no tile to carry a share on.
    final showsRoom =
        !showsMessages && (inCall || channel.kind == ChannelKind.voice);
    final conversation = showsRoom
        ? ListenableBuilder(
            listenable: Listenable.merge([goLive, viewer]),
            builder: (_, _) => room(),
          )
        : room();
    return Column(
      children: [
        ChatHeader(
          channel: channel,
          leading: switch (_recipientOf(channel)) {
            final person? => DirectMessageHeaderAvatar(person: person),
            null when channel.isGroupDirectMessage => GroupDirectMessageAvatar(
              channel: channel,
              size: DirectMessageHeaderAvatar.size,
            ),
            null => null,
          },
          status: showsRoom
              ? VoiceRoomStatusLine(controller: voice, channelId: channel.id)
              : null,
          // Only a thread has a membership to join; every other channel gets
          // nothing rather than a control that would have nothing to act on.
          threadMembership: channel.isThread
              ? ListenableBuilder(
                  listenable: threadMembership,
                  builder: (_, _) =>
                      ThreadMembershipButton(controller: threadMembership),
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
          showMembers: widget.showMembers,
          showPins: widget.showPins,
          showThreads: widget.showThreads,
          inboxSummary: InboxSummary.fromWorkspace(widget.workspace),
          onSelectChannel: widget.onPickChannel,
          onSelectVoiceSurface: (surface) =>
              workspaceController.selectVoiceSurface(channel.id, surface),
          onQueryChanged: workspaceController.setQuery,
          onSubmitQuery: widget.onSubmitQuery,
          onToggleMembers: widget.allowMemberPanel
              ? workspaceController.toggleMembers
              : null,
          onTogglePins: () {
            workspaceController.togglePins();
            if (workspaceController.showPins) {
              unawaited(chat.loadPinnedMessages(channel.id));
            }
          },
          onToggleThreads: widget.allowThreadPanel
              ? () {
                  workspaceController.toggleThreads();
                  final threadParentId = channel.threadParentId;
                  if (workspaceController.showThreads &&
                      threadParentId != null) {
                    // The panel lists every thread, whatever tags the forum
                    // view picked last for the same parent.
                    unawaited(
                      chat.loadThreads(
                        threadParentId,
                        refresh: true,
                        tagIds: const {},
                      ),
                    );
                  }
                }
              : null,
          onOpenInbox: widget.onOpenInbox,
        ),
        Expanded(child: conversation),
        if (showsMessages && !locked)
          ListenableBuilder(
            listenable: chat.activeChannelTyping,
            builder: (_, _) => TypingIndicator(
              members: chat.typingMembersFor(channel.id),
              spaceId: channel.spaceId,
            ),
          ),
        if (showsMessages && locked)
          const LockedThreadComposerNotice()
        else if (showsMessages && !widget.capabilities.sendMessages)
          const ReadOnlyChannelNotice()
        else if (showsMessages)
          MessageComposer(
            key: _composerKey,
            gifPicker: GifPickerScope.read(context),
            canAttachFiles: widget.capabilities.attachFiles,
            slashCommands: SlashCommandScope.read(context),
            expressionFavorites: ExpressionFavoritesScope.read(context),
            channelId: channel.id,
            channelName: channel.name,
            drafts: chat.drafts,
            replyTo: replyTo,
            replyAuthorName: replyTo == null
                ? null
                : widget.workspace
                      .memberOrNull(replyTo.authorId)
                      ?.displayNameFor(channel.spaceId),
            onCancelReply: () => _setReply(chat, null),
            onEditLastMessage: () =>
                _timelineKey.currentState?.editLastOwnMessage() ?? false,
            slowmode: Duration(seconds: channel.rateLimitPerUser),
            slowmodeUntil: _slowmodeUntil(chat),
            characterLimit: _characterLimit(),
            attachmentSizeLimitBytes: _attachmentSizeLimit(channel),
            channelHintPrefix: _composerHintPrefix(channel),
            spaceName: widget.workspace.spaceById(channel.spaceId).name,
            autocompleteCatalog: ComposerAutocompleteCatalog.fromWorkspace(
              widget.workspace,
              channel,
            ),
            onSearchMembers: channel.isDirectMessage
                ? null
                : (query) => chat.searchGuildMembers(
                    spaceId: channel.spaceId,
                    query: query,
                  ),
            emojiSections: emojiSectionsFromWorkspace(
              widget.workspace,
              channel.spaceId,
            ),
            stickerSections: stickerSectionsFromWorkspace(
              widget.workspace,
              channel.spaceId,
            ),
            isSending: chat.isSendingIn(channel.id),
            onTyping: () => chat.startTyping(channel.id),
            onCreatePoll: (poll) =>
                chat.createPoll(channelId: channel.id, poll: poll),
            onSendStickers: (stickerIds) => chat.sendStickers(
              channelId: channel.id,
              stickerIds: stickerIds,
            ),
            voiceMessageRecorder: VoiceMessageRecorderScope.maybeOf(context),
            onSendVoiceMessage:
                chat.canSendVoiceMessages &&
                    widget.capabilities.sendVoiceMessages
                ? (voiceMessage) => chat.sendVoiceMessage(
                    channelId: channel.id,
                    voiceMessage: voiceMessage,
                  )
                : null,
            onSend:
                (
                  body,
                  attachments,
                  replyToMessageId,
                  suppressNotifications,
                ) async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  final sent = await chat.sendMessage(
                    channelId: channel.id,
                    body: body,
                    attachments: attachments,
                    replyToMessageId: replyToMessageId,
                    suppressNotifications: suppressNotifications,
                  );
                  if (!sent) {
                    messenger?.showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        margin: _aboveComposer,
                        content: Text(
                          'Your message to ${_composerHintPrefix(channel)}'
                          '${channel.name} did not send. '
                          '${sendFailureReason(chat.error)}',
                        ),
                      ),
                    );
                    return false;
                  }
                  // A reply picked while this send ran is not this send's.
                  // The user may be in another channel by now.
                  final draft = chat.drafts.read(channel.id);
                  if (draft.replyTo?.id == replyToMessageId) {
                    chat.drafts.write(channel.id, draft.withReply(null));
                    if (mounted) setState(() {});
                  }
                  return true;
                },
          ),
      ],
    );
  }

  /// The longest message this account may type, from what it holds. A
  /// transport without entitlement data keeps the base length: it is what
  /// every free account gets, and typing past it is refused by the server.
  int _characterLimit() {
    final entitlements = AccountEntitlementsScope.maybeOf(
      context,
    )?.entitlements;
    return (entitlements?.premiumTier ?? PremiumTier.none)
        .messageCharacterLimit;
  }

  /// The largest file this account may attach in this channel, or null while
  /// the account's entitlements have not arrived. The answer is whichever is
  /// larger: what the account itself can upload, or what this server's boost
  /// level grants everybody in it.
  int? _attachmentSizeLimit(ConversationChannel channel) {
    final entitlements = AccountEntitlementsScope.maybeOf(
      context,
    )?.entitlements;
    if (entitlements == null) return null;
    return GuildUploadLimits.uploadLimitFor(
      guildTier: widget.workspace.spaceById(channel.spaceId).premiumTier,
      tier: entitlements.premiumTier,
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
    final channelId = widget.channel.id;
    return ongoing != null && !ongoing.unavailable
        ? () => unawaited(
            _reportCallFailure(
              controller,
              controller.joinOngoingCall(channelId),
            ),
          )
        : () => unawaited(
            _reportCallFailure(controller, controller.placeCall(channelId)),
          );
  }

  /// Waits for a call action and says why it failed, if it did. A call button
  /// that does nothing on a refusal reads as a broken button.
  Future<void> _reportCallFailure(
    DirectCallController controller,
    Future<void> action,
  ) async {
    await action;
    final error = controller.error;
    if (error == null || !mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(callFailureReason(error))));
  }

  /// The one other person in a DM, or null for a channel or a group DM.
  Member? _recipientOf(ConversationChannel channel) =>
      switch (channel.soleRecipientId) {
        final id? => widget.workspace.memberOrNull(id),
        null => null,
      };

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
    // The strip reads the store on every build, so a summary arriving
    // mid-conversation is drawn as soon as the controller announces it. An
    // empty channel draws none of it, which is the timeline the app shipped
    // before summaries existed.
    final summaries = chat.conversationSummariesFor(channel.id);
    return Column(
      children: [
        if (summaries.isNotEmpty)
          ConversationSummaries(
            workspace: widget.workspace,
            summaries: summaries,
            onSelect: (summary) =>
                _jumpToSummary(chat, workspaceController, summary),
          ),
        // The timeline itself is kept across rebuilds that leave the
        // conversation as it was, which is most of them: somebody typing, a
        // voice seat filling and a call ringing all redraw the pane without
        // changing a message.
        //
        // Listed below is everything it draws from, and of the workspace only
        // what its rows show. The controllers it also reads out of the scopes
        // above are not listed, because a scope hands out the same instance
        // for the life of the session; were one to be swapped, the timeline
        // would keep the old one.
        Expanded(
          child: CachedSubtree(
            dependencies: [
              ...timelineDependencies(widget.workspace, channel),
              channel,
              widget.capabilities,
              workspaceController.query,
              workspaceController.targetMessageId,
              workspaceController.targetRequest,
              chat.hasNewerMessages(channel.id),
              chat.historyWindowError(channel.id),
              chat.lastSentMessageIdIn(channel.id),
              chat.canLoadOlderMessages(channel.id),
              chat.isLoadingOlderMessages(channel.id),
              chat.olderMessagesError(channel.id),
            ],
            // One group, so Tab walks the rows in order. Without it, the order
            // goes by height on screen and mixes in the rail and the sidebar.
            builder: (_) => FocusTraversalGroup(
              child: _timeline(chat, workspaceController),
            ),
          ),
        ),
      ],
    );
  }

  /// Takes the reader to a message, by the same route the inbox and search
  /// results take: the selection points at the message and the channel opens
  /// built around it.
  void _jumpToMessage(
    ChatController chat,
    WorkspaceController workspaceController,
    String channelId,
    String messageId,
  ) {
    workspaceController.selectMessage(channelId, messageId);
    unawaited(chat.openChannel(channelId, anchorMessageId: messageId));
  }

  void _jumpToSummary(
    ChatController chat,
    WorkspaceController workspaceController,
    ConversationSummary summary,
  ) {
    if (summary.startMessageId.isEmpty) return;
    _jumpToMessage(
      chat,
      workspaceController,
      summary.channelId,
      summary.startMessageId,
    );
  }

  Widget _timeline(
    ChatController chat,
    WorkspaceController workspaceController,
  ) {
    final channel = widget.channel;
    return MessageList(
      key: _timelineKey,
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
      targetRequest: workspaceController.targetRequest,
      lastSentMessageId: chat.lastSentMessageIdIn(channel.id),
      hasNewerMessages: chat.hasNewerMessages(channel.id),
      windowError: chat.historyWindowError(channel.id),
      readingPositions: workspaceController.readingPositions,
      onOpenMessage: (messageId) =>
          _jumpToMessage(chat, workspaceController, channel.id, messageId),
      onLoadPresent: () => unawaited(chat.jumpToPresent(channel.id)),
      onReply: (message) => _setReply(chat, message),
      onEdit: chat.editMessage,
      onEditClosed: focusComposer,
      onDelete: chat.deleteMessage,
      onToggleReaction: chat.toggleReaction,
      onLoadReactionUsers: chat.loadReactionUsers,
      onAddReaction: chat.addReaction,
      onMarkUnread: chat.readStateRepository == null
          ? null
          : chat.markChannelUnreadFrom,
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
      onOpenMemberProfile: widget.onOpenMemberProfile,
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
        isFirstDirectMessage: _isFirstDirectMessage(widget.workspace, message),
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
    final inChannel = workspace.messagesFor(message.channelId);
    return inChannel.length == 1 &&
        inChannel.single.id == message.id &&
        message.authorId != workspace.currentMemberId;
  }
}
