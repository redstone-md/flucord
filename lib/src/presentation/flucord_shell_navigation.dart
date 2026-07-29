part of 'flucord_shell.dart';

extension _FlucordShellNavigation on FlucordShell {
  /// What stands in for the workspace when there are no spaces to show: the
  /// OAuth account's guild directory when one is signed in, and otherwise the
  /// prompt to connect a transport.
  Widget _buildEmptyWorkspace(BuildContext context) {
    if (connectionController.mode != SessionMode.disconnected) {
      return EmptyWorkspaceView(
        onOpenConnections: () => _openConnections(context),
      );
    }
    final account = discordOAuthController.account;
    if (account == null) {
      return DisconnectedWorkspaceView(
        onOpenConnections: () => _openConnections(context),
      );
    }
    oauthGuildDirectoryController.reconcile(account);
    return ListenableBuilder(
      listenable: oauthGuildDirectoryController,
      builder: (context, _) => OAuthGuildWorkspace(
        account: account,
        accountHomeSelected: oauthGuildDirectoryController.accountHomeSelected,
        membershipController: oauthGuildMembershipController,
        selectedGuildId: oauthGuildDirectoryController.selectedGuildId,
        onOpenAccountHome: oauthGuildDirectoryController.selectAccountHome,
        onSelectGuild: (guildId) =>
            oauthGuildDirectoryController.selectGuild(account, guildId),
        onOpenConnections: () => _openConnections(context),
        onToggleTheme: workspaceController.toggleTheme,
        isDark: workspaceController.themeMode == ThemeMode.dark,
      ),
    );
  }

  /// Floats the incoming-call card over [body].
  ///
  /// A ring is not addressed to the open channel, so the surface cannot live in
  /// the conversation pane: it has to reach the user wherever they are. When no
  /// call is ringing the overlay collapses to nothing and the stack is a single
  /// child, so the workspace pays nothing for it.
  Widget _withIncomingCall(ChatWorkspace workspace, Widget body) {
    final controller = directCallController;
    if (controller == null) return body;
    return Stack(
      children: [
        body,
        IncomingCallOverlay(controller: controller, workspace: workspace),
      ],
    );
  }

  /// Turns a sidebar notification menu choice into a controller call.
  ///
  /// A null [channel] means the menu was raised on the space itself. The two
  /// scopes share every row, so the routing lives here rather than in six
  /// callbacks threaded through the sidebar.
  void _applyNotificationRequest(
    NotificationMenuRequest request, {
    required CommunitySpace space,
    required ConversationChannel? channel,
  }) {
    switch (request) {
      case MarkReadRequest():
        if (channel == null) {
          unawaited(chatController.markSpaceRead(space.id));
        } else {
          chatController.acknowledgeChannel(channel.id, immediate: true);
        }
      case MuteRequest():
        unawaited(
          channel == null
              ? chatController.setSpaceMuted(
                  space.id,
                  muted: request.muted,
                  windowSeconds: request.windowSeconds,
                )
              : chatController.setChannelMuted(
                  channel,
                  muted: request.muted,
                  windowSeconds: request.windowSeconds,
                ),
        );
      case NotificationLevelRequest():
        unawaited(
          channel == null
              ? chatController.setSpaceNotificationLevel(
                  space.id,
                  request.level,
                )
              : chatController.setChannelNotificationLevel(
                  channel,
                  request.level,
                ),
        );
      case SuppressEveryoneRequest():
        unawaited(
          chatController.setSpaceSuppressEveryone(space.id, request.value),
        );
      case MobilePushRequest():
        unawaited(chatController.setSpaceMobilePush(space.id, request.value));
    }
  }

  void _openConnections(BuildContext context) {
    final desktopLoginController = DiscordDesktopLoginScope.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => ConnectionDialog(
        controller: connectionController,
        desktopLoginController: desktopLoginController,
      ),
    );
  }

  Future<void> _openInbox(BuildContext context) async {
    final target = await showDialog<InboxTarget>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (_) => ListenableBuilder(
        listenable: chatController,
        builder: (dialogContext, _) => InboxDialog(
          catalog: InboxCatalog.fromWorkspace(chatController.workspace!),
          onMarkAllRead: chatController.markAllChannelsRead,
        ),
      ),
    );
    if (target == null || !context.mounted) return;
    _openDestination(
      spaceId: target.spaceId,
      channelId: target.channelId,
      messageId: target.messageId,
      voiceSurface: VoiceChannelSurface.chat,
    );
  }

  Future<void> _openScheduledEvents(
    BuildContext context,
    CommunitySpace space,
  ) async {
    // Discord withholds the affordance rather than the request: an account
    // without Manage Events sees the list and none of the controls.
    final canManage = WorkspacePermissions(
      chatController.workspace!,
      memberId: chatController.workspace!.currentMemberId,
    ).administrationOf(space.id).canManageEvents;
    final channelId = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (_) => ListenableBuilder(
        listenable: chatController,
        builder: (dialogContext, _) => GuildScheduledEventsDialog(
          space: space,
          workspace: chatController.workspace!,
          events: chatController.scheduledEventsFor(space.id),
          isLoading: chatController.isLoadingScheduledEvents(space.id),
          error: chatController.scheduledEventsError(space.id),
          onRefresh: () => chatController.loadScheduledEvents(space.id),
          onSetInterest: chatController.setEventInterest,
          attendeesFor: chatController.eventAttendeesFor,
          onShowAttendees: (event) =>
              unawaited(chatController.loadEventAttendees(event)),
          onCreate: canManage
              ? () => unawaited(_openEventForm(context, space))
              : null,
          onEdit: canManage
              ? (event) =>
                    unawaited(_openEventForm(context, space, event: event))
              : null,
          onDelete: canManage
              ? (event) => unawaited(_confirmDeleteEvent(context, event))
              : null,
        ),
      ),
    );
    if (channelId == null || !context.mounted) return;
    _openDestination(spaceId: space.id, channelId: channelId);
  }

  /// Opens the create or edit form for a server event.
  Future<void> _openEventForm(
    BuildContext context,
    CommunitySpace space, {
    GuildScheduledEvent? event,
  }) async {
    final workspace = chatController.workspace;
    if (workspace == null) return;
    final channels = [
      for (final channel in workspace.channels)
        if (channel.spaceId == space.id && channel.kind == ChannelKind.voice)
          channel,
    ];
    final result = await showDialog<GuildEventFormResult>(
      context: context,
      builder: (_) => GuildEventFormDialog(channels: channels, event: event),
    );
    if (result == null) return;
    if (result.edit case final edit? when event != null) {
      await chatController.editScheduledEvent(event, edit);
      return;
    }
    if (result.draft case final draft?) {
      await chatController.createScheduledEvent(space.id, draft);
    }
  }

  /// Deletes an event, after asking. Deleting one cannot be undone from here.
  Future<void> _confirmDeleteEvent(
    BuildContext context,
    GuildScheduledEvent event,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('guild-event-delete-confirm'),
        title: const Text('Delete this event?'),
        content: Text('${event.name} will be removed for everybody.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('guild-event-delete-accept'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await chatController.deleteScheduledEvent(event);
  }

  /// Opens the server-settings window for [space].
  ///
  /// The controller is built per opening and disposed with the dialog: it holds
  /// a whole guild's roles, bans and audit pages, and keeping one alive per
  /// guild the user ever glanced at would pin all of it for the session.
  Future<void> _openGuildSettings(
    BuildContext context,
    CommunitySpace space,
    GuildAdminCapabilities capabilities,
  ) async {
    final repository = chatController.guildManagement;
    final workspace = chatController.workspace;
    if (repository == null || workspace == null) return;
    final controller = GuildSettingsController(
      repository,
      capabilities,
      guildId: space.id,
    );
    try {
      await showGuildSettingsDialog(
        context: context,
        controller: controller,
        space: space,
        workspace: workspace,
      );
    } finally {
      controller.dispose();
    }
  }

  /// Opens the in-app report flow for [member].
  Future<void> _reportMember(BuildContext context, Member member) async {
    final repository = chatController.moderation;
    if (repository == null) return;
    final spaceId = workspaceController.selectedSpaceId;
    final controller = ReportFlowController(
      repository,
      target: UserReportTarget(
        userId: member.id,
        guildId: spaceId == CommunitySpace.directMessagesId ? null : spaceId,
      ),
    );
    try {
      await showReportDialog(context: context, controller: controller);
    } finally {
      controller.dispose();
    }
  }

  /// Opens the in-app report flow for one message.
  ///
  /// A first DM from somebody not yet spoken to has its own report type, and
  /// its own menu, so the target says which it is rather than the surface
  /// guessing after the menu comes back.
  Future<void> _reportMessage(BuildContext context, ChatMessage message) async {
    final repository = chatController.moderation;
    if (repository == null) return;
    final controller = ReportFlowController(
      repository,
      target: MessageReportTarget(
        channelId: message.channelId,
        messageId: message.id,
        isFirstDirectMessage: _isFirstDirectMessage(message),
      ),
    );
    try {
      await showReportDialog(context: context, controller: controller);
    } finally {
      controller.dispose();
    }
  }

  /// Opens the in-app report flow for a whole server.
  Future<void> _reportSpace(BuildContext context, CommunitySpace space) async {
    final repository = chatController.moderation;
    if (repository == null) return;
    final controller = ReportFlowController(
      repository,
      target: GuildReportTarget(space.id),
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
  bool _isFirstDirectMessage(ChatMessage message) {
    final workspace = chatController.workspace;
    if (workspace == null) return false;
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

  /// Blocks [member], after a confirmation. Blocking is not undoable from any
  /// surface Flucord has yet, so it asks first.
  Future<void> _blockMember(BuildContext context, Member member) async {
    final repository = chatController.moderation;
    if (repository == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('block-member-dialog'),
        title: Text('Block ${member.displayName}?'),
        content: const Text(
          'You will stop seeing their messages and they cannot message you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('block-member-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repository.blockUser(member.id);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That member could not be blocked')),
      );
    }
  }

  /// Like the channel sidebar, the quick switcher is a "go to this channel"
  /// gesture, so it hands a voice channel back on whichever surface that
  /// channel was last left on rather than forcing one.
  void _openQuickSwitcherDestination(QuickSwitcherDestination destination) =>
      _openDestination(
        spaceId: destination.spaceId,
        channelId: destination.channelId,
      );

  void _selectChannel(String channelId, {VoiceChannelSurface? voiceSurface}) {
    workspaceController.selectChannel(channelId, surface: voiceSurface);
    unawaited(chatController.openChannel(channelId));
  }

  void _openDestination({
    required String spaceId,
    String? channelId,
    String? messageId,
    VoiceChannelSurface? voiceSurface,
  }) {
    final workspace = chatController.workspace;
    if (workspace == null) return;
    if (channelId != null && workspace.channelOrNull(channelId) == null) return;
    workspaceController.selectSpace(workspace, spaceId);
    if (channelId != null && messageId != null) {
      workspaceController.selectMessage(channelId, messageId);
    } else if (channelId != null) {
      workspaceController.selectChannel(channelId, surface: voiceSurface);
    }
    final selectedChannelId = workspaceController.selectedChannelId;
    if (selectedChannelId != null) {
      unawaited(
        chatController.openChannel(
          selectedChannelId,
          anchorMessageId: messageId,
        ),
      );
    }
  }

  Future<void> _openDirectMessage(BuildContext context) async {
    final recipientId = await showDialog<String>(
      context: context,
      builder: (_) => const DirectMessageDialog(),
    );
    if (recipientId == null || !context.mounted) return;
    await _openDirectConversation(context, recipientId);
  }

  Future<void> _openDirectConversation(
    BuildContext context,
    String recipientId,
  ) async {
    final channelId = await chatController.openDirectConversation(recipientId);
    if (!context.mounted) return;
    if (channelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Direct message could not be opened')),
      );
      return;
    }
    final workspace = chatController.workspace!;
    final channel = workspace.channelById(channelId);
    _openDestination(spaceId: channel.spaceId, channelId: channel.id);
  }
}
