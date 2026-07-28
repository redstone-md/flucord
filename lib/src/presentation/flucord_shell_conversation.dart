part of 'flucord_shell.dart';

extension _FlucordShellConversation on FlucordShell {
  /// Builds the pane for the selected channel.
  ///
  /// It lives in its own part because it is the widest wiring point in the app
  /// — every message action, every panel toggle and now the call plane arrive
  /// here — and burying the workspace's own layout inside that argument list
  /// made both harder to read than either is alone.
  Widget _conversationPane({
    required BuildContext context,
    required ChatWorkspace workspace,
    required ChannelCapabilities capabilities,
    required ConversationChannel channel,
    required List<ConversationChannel> channels,
    required CommunitySpace space,
    required bool showChannels,
    required bool membersFit,
    required bool showMembers,
    required bool showPins,
    required bool showThreads,
    required String? threadParentId,
    required bool allowThreadPanel,
    required VoiceChannelSurface voiceSurface,
    required InboxSummary inboxSummary,
    required bool canSearch,
  }) => _ConversationPane(
    workspace: workspace,
    capabilities: capabilities,
    externalLinkLauncher: externalLinkLauncher,
    attachmentDownloadService: attachmentDownloadService,
    channel: channel,
    channels: channels,
    query: workspaceController.query,
    targetMessageId: workspaceController.targetMessageId,
    compact: !showChannels,
    voiceSurface: voiceSurface,
    onSelectVoiceSurface: (surface) =>
        workspaceController.selectVoiceSurface(channel.id, surface),
    onPickChannel: _selectChannel,
    allowMemberPanel: membersFit && !space.isDirectMessages,
    allowThreadPanel: allowThreadPanel,
    showMembers: showMembers,
    showPins: showPins,
    showThreads: showThreads,
    forumArchivedPosts:
        channel.kind == ChannelKind.forum || channel.kind == ChannelKind.media
        ? chatController.archivedThreadsFor(channel.id)
        : const [],
    isLoadingForumPosts: chatController.isLoadingArchivedThreads(channel.id),
    forumPostsError: chatController.archivedThreadsError(channel.id),
    canLoadMoreForumPosts: chatController.canLoadMoreArchivedThreads(
      channel.id,
    ),
    inboxSummary: inboxSummary,
    typingMembers: chatController.typingMembersFor(channel.id),
    isSending: chatController.isSending,
    isLoading: chatController.isChannelLoading(channel.id),
    loadError: chatController.channelError(channel.id),
    canLoadOlder: chatController.canLoadOlderMessages(channel.id),
    isLoadingOlder: chatController.isLoadingOlderMessages(channel.id),
    olderLoadError: chatController.olderMessagesError(channel.id),
    onLoadOlder: () => unawaited(chatController.loadOlderMessages(channel.id)),
    onRetry: () => chatController.openChannel(channel.id, refresh: true),
    onSelectChannel: (id) =>
        _selectChannel(id, voiceSurface: VoiceChannelSurface.chat),
    onQueryChanged: workspaceController.setQuery,
    onSubmitQuery: canSearch
        ? (text) => _submitSearch(workspace, space, channel, text)
        : null,
    onToggleMembers: workspaceController.toggleMembers,
    onTogglePins: () {
      workspaceController.togglePins();
      if (workspaceController.showPins) {
        unawaited(chatController.loadPinnedMessages(channel.id));
      }
    },
    onToggleThreads: () {
      workspaceController.toggleThreads();
      if (workspaceController.showThreads && threadParentId != null) {
        unawaited(chatController.loadArchivedThreads(threadParentId));
      }
    },
    onRefreshForumPosts: () => unawaited(
      chatController.loadArchivedThreads(channel.id, refresh: true),
    ),
    onLoadMoreForumPosts: () =>
        unawaited(chatController.loadArchivedThreads(channel.id)),
    onLoadForumPostPreview: (postId) =>
        unawaited(chatController.loadForumPostPreview(postId)),
    onCreateForumPost: (name, content, attachments, duration, tagIds) async {
      final thread = await chatController.createForumPost(
        channelId: channel.id,
        name: name,
        content: content,
        autoArchiveDurationMinutes: duration,
        attachments: attachments,
        appliedTagIds: tagIds,
      );
      if (thread == null) return false;
      _selectChannel(thread.id);
      return true;
    },
    onOpenInbox: () => _openInbox(context),
    onSend: (body, attachments, replyToMessageId, suppressNotifications) =>
        chatController.sendMessage(
          channelId: channel.id,
          body: body,
          attachments: attachments,
          replyToMessageId: replyToMessageId,
          suppressNotifications: suppressNotifications,
        ),
    onCreatePoll: (poll) =>
        chatController.createPoll(channelId: channel.id, poll: poll),
    onSendStickers: (stickerIds) => chatController.sendStickers(
      channelId: channel.id,
      stickerIds: stickerIds,
    ),
    onEdit: chatController.editMessage,
    onDelete: chatController.deleteMessage,
    onToggleReaction: chatController.toggleReaction,
    onLoadReactionUsers: chatController.loadReactionUsers,
    onAddReaction: chatController.addReaction,
    onCreateThread: (message, name, duration) async {
      final thread = await chatController.createThreadFromMessage(
        message,
        name: name,
        autoArchiveDurationMinutes: duration,
      );
      if (thread == null) return false;
      _selectChannel(thread.id);
      return true;
    },
    onTogglePin: chatController.togglePin,
    onResolveAlert: chatController.resolveAutoModAlert,
    onEndPoll: chatController.endPoll,
    onForward: (message, targetChannelId) async {
      final forwarded = await chatController.forwardMessage(
        message,
        targetChannelId,
      );
      if (!forwarded) return false;
      _selectChannel(targetChannelId, voiceSurface: VoiceChannelSurface.chat);
      return true;
    },
    onToggleSuppressEmbeds: chatController.toggleSuppressEmbeds,
    onTyping: () => chatController.startTyping(channel.id),
    voiceController: voiceController,
    threadMembershipController: threadMembershipController,
    stageController: stageController,
    soundboardController: soundboardController,
    goLiveController: goLiveController,
    streamViewerController: streamViewerController,
    gifPickerController: gifPickerController,
    slashCommandController: slashCommandController,
    messageComponentController: messageComponentController,
    voiceMessageRecorder: voiceMessageRecorder,
    onSendVoiceMessage: (voiceMessage) => chatController.sendVoiceMessage(
      channelId: channel.id,
      voiceMessage: voiceMessage,
    ),
    directCallController: directCallController,
  );

  /// Runs [text] against the server and opens the results panel.
  ///
  /// The scope is the guild, because that is the corpus Discord's guild route
  /// answers about; narrowing it to one channel is what the `in:` filter does.
  /// A private conversation has no guild, so it searches its own channel.
  ///
  /// The channels the `in:` filter may name are exactly the ones this account
  /// can read the history of. Resolving a name the account cannot read would
  /// ask the server about a channel it is not allowed to see.
  void _submitSearch(
    ChatWorkspace workspace,
    CommunitySpace space,
    ConversationChannel channel,
    String text,
  ) {
    final controller = messageSearchController;
    if (controller == null) return;
    final permissions = WorkspacePermissions(workspace);
    workspaceController.openSearch();
    unawaited(
      controller.search(
        scope: space.isDirectMessages
            ? ChannelMessageSearchScope(channel.id)
            : GuildMessageSearchScope(space.id),
        text: text,
        grammar: MessageSearchGrammar(
          channels: space.isDirectMessages
              ? [channel]
              : [
                  for (final item in permissions.visibleChannelsFor(space.id))
                    if (permissions.can(
                      DiscordPermissions.readMessageHistory,
                      item,
                    ))
                      item,
                ],
          members: workspace.members,
          currentMemberId: workspace.currentMemberId,
        ),
      ),
    );
  }
}
