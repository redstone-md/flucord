part of 'flucord_shell.dart';

extension _FlucordShellNavigation on FlucordShell {
  /// What stands in for the workspace when there are no spaces to show: the
  /// OAuth account's guild directory when one is signed in, and otherwise the
  /// sign-in screen.
  Widget _buildEmptyWorkspace(BuildContext context) {
    if (connectionController.isBusy) return const LoadingWorkspaceView();
    if (connectionController.mode != SessionMode.disconnected) {
      return EmptyWorkspaceView(
        onOpenConnections: () => _openConnections(context),
      );
    }
    final account = discordOAuthController.account;
    if (account == null) {
      return DisconnectedWorkspaceView(
        connection: connectionController,
        login: DiscordDesktopLoginScope.of(context),
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
        onToggleTheme: onToggleTheme,
        isDark: themeMode == ThemeMode.dark,
      ),
    );
  }

  /// Puts the connection banner above [body] and the incoming-call card over it.
  ///
  /// A demo has no connection to report, so it gets no banner.
  Widget _withWorkspaceChrome(ChatWorkspace workspace, Widget body) => Column(
    children: [
      if (connectionController.mode == SessionMode.discord)
        ConnectionBanner(
          status: chatController.connectionStatus,
          onRetry: connectionController.hasSavedCredential
              ? () => unawaited(connectionController.connectSavedCredential())
              : null,
        ),
      Expanded(child: _withIncomingCall(workspace, body)),
    ],
  );

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
    // Opening the centre is what acks it: the dialog below is a snapshot of
    // what was waiting, so its rows stay listed while the badge goes quiet.
    chatController.acknowledgeNotificationCentre();
    final target = await showDialog<InboxTarget>(
      context: context,
      // The inbox is a snapshot of what was waiting when it was opened, not a
      // live feed. Following the chat controller here rebuilt the whole
      // catalogue on every gateway event — on a busy account that is every
      // frame the dialog is on screen — and shuffled the list under the reader
      // while they were reading it. Marking everything read is the one action
      // that changes what it shows, so it asks for the rebuild itself.
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => InboxDialog(
          catalog: InboxCatalog.fromWorkspace(chatController.workspace!),
          onMarkAllRead: () {
            chatController.markAllChannelsRead();
            setDialogState(() {});
          },
          onMarkEntryRead: (channelId) {
            chatController.acknowledgeChannel(channelId, immediate: true);
            setDialogState(() {});
          },
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
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete this event?',
      message: '${event.name} will be removed for everybody.',
      confirmLabel: 'Delete',
      dialogKey: const ValueKey('guild-event-delete-confirm'),
      confirmKey: const ValueKey('guild-event-delete-accept'),
    );
    if (confirmed) await chatController.deleteScheduledEvent(event);
  }

  /// Whether the settings window has anything to show this account.
  bool _canOpenSettings(GuildAdminCapabilities administration) =>
      administration.hasAnySurface && chatController.guildManagement != null;

  /// The menu of a server on the rail, which may not be the one on screen. It
  /// holds what the server's header offers, and Mark as read up front.
  Future<void> _openSpaceMenu(
    BuildContext context,
    String spaceId,
    Offset position,
  ) async {
    final workspace = chatController.workspace;
    final space = workspace?.spaceOrNull(spaceId);
    if (workspace == null || space == null) return;
    final administration = WorkspacePermissions(
      workspace,
    ).administrationOf(spaceId);
    final items = serverMenuItems({
      if (chatController.readStateRepository != null) ...{
        ServerMenuAction.markRead,
        ServerMenuAction.notifications,
      },
      if (_canOpenSettings(administration)) ServerMenuAction.settings,
      if (chatController.moderation != null) ServerMenuAction.report,
      if (chatController.guildManagement != null) ServerMenuAction.leave,
    });
    // A transport with none of these, like the demo, has no menu to show.
    if (items.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = RelativeRect.fromRect(
      overlay.globalToLocal(position) & Size.zero,
      Offset.zero & overlay.size,
    );
    final action = await showMenu<ServerMenuAction>(
      context: context,
      position: at,
      items: items,
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case ServerMenuAction.markRead:
        await chatController.markSpaceRead(space.id);
      case ServerMenuAction.settings:
        await _openGuildSettings(context, space, administration);
      case ServerMenuAction.notifications:
        await _openSpaceNotificationMenu(context, space, at);
      case ServerMenuAction.report:
        await _reportSpace(context, space);
      case ServerMenuAction.leave:
        await _leaveServer(context, space);
    }
  }

  Future<void> _openSpaceNotificationMenu(
    BuildContext context,
    CommunitySpace space,
    RelativeRect at,
  ) async {
    final readState = chatController.readState;
    final settings = readState.settingsFor(space.id);
    final request = await showNotificationSettingsMenu(
      context: context,
      position: at,
      muted: readState.isSpaceMuted(space.id),
      level: readState.spaceNotificationLevel(space.id),
      isSpaceScope: true,
      suppressEveryone: settings.suppressEveryone,
      mobilePush: settings.mobilePush,
    );
    if (request == null) return;
    _applyNotificationRequest(request, space: space, channel: null);
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
      // The expression plane and the soundboard are read live off the
      // session the same way the guild-management repository is, so a
      // swapped transport leaves no controller talking to a closed socket.
      expressions: chatController.expressions,
      soundboard: chatController.soundboard,
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

  /// The moderation controller for one member's popover, or null where the
  /// account holds no guild-administration plane.
  ///
  /// Built per popover and disposed with it, like the settings window's
  /// controller: it holds a member's standing and the guild's roles, and
  /// keeping one alive per member ever clicked would pin all of it.
  GuildMemberAdminController? _memberAdminController(
    String spaceId,
    String userId,
  ) {
    final repository = chatController.guildManagement;
    final workspace = chatController.workspace;
    if (repository == null || workspace == null) return null;
    return GuildMemberAdminController(
      repository,
      WorkspacePermissions(
        workspace,
        memberId: workspace.currentMemberId,
      ).administrationOf(spaceId),
      guildId: spaceId,
      userId: userId,
    );
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

  /// Runs the add-server flow and lands the user in whatever it gained.
  Future<void> _addServer(BuildContext context) async {
    final spaceId = await showAddServerFlow(context, chat: chatController);
    if (spaceId == null || !context.mounted) return;
    _selectSpace(spaceId);
  }

  /// Leaves [space], after asking. Leaving is not undoable from any surface
  /// Flucord has, so it confirms first, and a refusal from the server (an
  /// owner leaving their own server) is shown as the message it is.
  Future<void> _leaveServer(BuildContext context, CommunitySpace space) async {
    final confirmed = await showLeaveServerConfirmation(context, space: space);
    if (!confirmed || !context.mounted) return;
    final left = await chatController.leaveGuild(space.id);
    if (!context.mounted) return;
    if (!left) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            chatController.guildAccessError ?? 'The server was not left.',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('You left ${space.name}.')));
  }

  /// Blocks [member], after a confirmation. Blocking is not undoable from any
  /// surface Flucord has yet, so it asks first.
  Future<void> _blockMember(BuildContext context, Member member) async {
    final repository = chatController.moderation;
    if (repository == null) return;
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Block ${member.displayName}?',
      message:
          'You will stop seeing their messages and they cannot message you.',
      confirmLabel: 'Block',
      dialogKey: const ValueKey('block-member-dialog'),
      confirmKey: const ValueKey('block-member-confirm'),
    );
    if (!confirmed) return;
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

  /// Takes one step through the channels or the servers, from the keyboard.
  void _takeStep(ShellStep step) {
    switch (step) {
      case ShellStep.previousChannel:
        _stepChannel(-1, (_) => true);
      case ShellStep.nextChannel:
        _stepChannel(1, (_) => true);
      case ShellStep.previousUnreadChannel:
        _stepChannel(-1, chatController.readState.showsUnread);
      case ShellStep.nextUnreadChannel:
        _stepChannel(1, chatController.readState.showsUnread);
      case ShellStep.previousMentionChannel:
        _stepChannel(-1, (channel) => channel.mentionCount > 0);
      case ShellStep.nextMentionChannel:
        _stepChannel(1, (channel) => channel.mentionCount > 0);
      case ShellStep.previousServer:
        _stepServer(-1);
      case ShellStep.nextServer:
        _stepServer(1);
    }
  }

  /// Goes to the nearest channel [wanted] accepts in the [direction], walking
  /// the rows of the sidebar and wrapping at the ends. It passes voice channels,
  /// because opening a room unasked would reach for the microphone.
  void _stepChannel(
    int direction,
    bool Function(ConversationChannel channel) wanted,
  ) {
    final workspace = chatController.workspace;
    final spaceId = workspaceController.selectedSpaceId;
    if (workspace == null || spaceId == null) return;
    final selectedId = workspaceController.selectedChannelId;
    final rows = ChannelSidebarOrder(
      space: workspace.spaceById(spaceId),
      channels: WorkspacePermissions(workspace).visibleChannelsFor(spaceId),
      categories: workspace.categoriesFor(spaceId),
      collapsedCategoryIds: workspaceController.collapsedCategoryIds,
      selectedChannelId: selectedId,
      readState: chatController.readState,
      channelOf: _channelOf,
    ).rows.where((channel) => channel.kind != ChannelKind.voice).toList();
    final selected = rows.indexWhere((channel) => channel.id == selectedId);
    // With no selected row, the walk starts just outside the end it moves from.
    final start = selected >= 0 || direction > 0 ? selected : rows.length;
    for (var moved = 1; moved <= rows.length; moved++) {
      final channel = rows[(start + direction * moved) % rows.length];
      if (wanted(channel)) {
        _selectChannel(channel.id);
        return;
      }
    }
  }

  /// Goes to the next server in the order of the rail, where the direct
  /// messages stand first.
  void _stepServer(int direction) {
    final spaces = chatController.workspace?.spaces;
    if (spaces == null) return;
    final rail = [
      ...spaces.where((space) => space.isDirectMessages),
      ...spaces.where((space) => !space.isDirectMessages),
    ];
    final selected = rail.indexWhere(
      (space) => space.id == workspaceController.selectedSpaceId,
    );
    _selectSpace(rail[(selected + direction) % rail.length].id);
  }

  /// Opens a channel the back or forward key went to. It may be gone by now.
  void _openChannelFromHistory(String channelId) {
    final channel = _channelOf(channelId);
    if (channel == null) return;
    _openDestination(spaceId: channel.spaceId, channelId: channelId);
  }

  void _selectChannel(String channelId, {VoiceChannelSurface? voiceSurface}) {
    _leaveFriendsPageFor(channelId);
    workspaceController.selectChannel(channelId, surface: voiceSurface);
    unawaited(chatController.openChannel(channelId));
  }

  /// Walks back to the Room the account is connected to, from any server and
  /// from the channel's chat.
  void _openVoiceRoom(String channelId) {
    final channel = _channelOf(channelId);
    if (channel == null) return;
    _openDestination(
      spaceId: channel.spaceId,
      channelId: channelId,
      voiceSurface: VoiceChannelSurface.room,
    );
  }

  /// Opening a DM leaves the Friends page, as on Discord. A channel in a
  /// server does not: back in direct messages the page is still there.
  void _leaveFriendsPageFor(String channelId) {
    if (_channelOf(channelId)?.spaceId == CommunitySpace.directMessagesId) {
      friendsController?.closePanel();
    }
  }

  /// The Friends page in the canvas, with the inbox at its header's end.
  Widget _friendsPage(
    BuildContext context,
    ChatWorkspace workspace,
    FriendsController friends,
  ) => _WatchPresences(
    // Everyone the page can show with a status: every relationship tab,
    // and the suggestions under Add Friend.
    userIds: [
      for (final entry in friends.all) entry.user.id,
      for (final suggestion in friends.suggestions) suggestion.userId,
    ],
    builder: (_) => FriendsPanel(
      controller: friends,
      // From the workspace as it stands, which the presence service keeps
      // current; a second copy would be a second thing to go stale.
      presenceOf: (userId) =>
          chatController.workspace?.memberOrNull(userId)?.presence,
      onMessage: (userId) =>
          unawaited(_openDirectConversation(context, userId)),
      onOpenProfile: (userId, anchor) => unawaited(
        _openMemberCard(
          context,
          CommunitySpace.directMessagesId,
          userId,
          anchor,
        ),
      ),
      inbox: InboxActivityButton(
        summary: InboxSummary.fromWorkspace(workspace),
        onPressed: () => unawaited(_openInbox(context)),
      ),
    ),
  );

  /// Builds [build] again whenever someone takes or leaves a voice seat. Only
  /// the seats: the voice controller itself also fires on every speaking
  /// change, which these views do not show.
  Widget _onSeats(
    Widget Function(Map<String, List<VoiceParticipantStateEvent>> seated) build,
  ) => ListenableBuilder(
    listenable: voiceController.seats,
    builder: (_, _) => build(voiceController.seatedByChannel),
  );

  /// The friends doing something now. Built again when a friend's presence
  /// moves, from the workspace as it stands then.
  Widget _activeNow(ChatWorkspace workspace, FriendsController friends) {
    final users = [for (final friend in friends.friends) friend.user];
    return _onSeats(
      (seated) => _WatchPresences(
        userIds: [for (final user in users) user.id],
        builder: (_) => ActiveNowColumn(
          friends: activeFriends(
            users,
            workspace: chatController.workspace ?? workspace,
            seatedByChannel: seated,
          ),
          onOpenRoom: (channel) => _openVoiceRoom(channel.id),
        ),
      ),
    );
  }

  /// The name of the server [channelId] is in, or null for a call.
  String? _serverNameOf(String channelId) {
    final guildId = _channelOf(channelId)?.guildId;
    if (guildId == null) return null;
    return chatController.workspace?.spaceOrNull(guildId)?.name;
  }

  /// Looks a member up in the workspace as it stands.
  ///
  /// Handed to kept subtrees so a row drawn from an older build still reads the
  /// current table. What such a subtree *shows* is named in its dependencies,
  /// so it is redrawn when one of those members changes; this only keeps the
  /// answer honest in between.
  Member? _memberOf(String userId) =>
      chatController.workspace?.memberOrNull(userId);

  /// Looks a channel up in the workspace as it stands. Same reasoning as
  /// [_memberOf].
  ConversationChannel? _channelOf(String channelId) =>
      chatController.workspace?.channelOrNull(channelId);

  /// The members the channel sidebar actually draws: whoever is seated in a
  /// voice channel it lists, and the person on the other side of each direct
  /// message.
  ///
  /// Named as a dependency so a presence landing in one of a couple of hundred
  /// spaces redraws the sidebar only when it belongs to somebody on screen.
  /// Members keep their identity until they change, so an unchanged list
  /// compares equal.
  List<Member?> _shownMembers(
    ChatWorkspace workspace, {
    required List<ConversationChannel> channels,
    required Map<String, List<VoiceParticipantStateEvent>> seats,
  }) => [
    for (final channel in channels)
      if (channel.soleRecipientId case final recipientId?)
        workspace.memberOrNull(recipientId),
    for (final channel in channels)
      for (final seat in seats[channel.id] ?? const [])
        workspace.memberOrNull(seat.userId),
  ];

  /// Opens [spaceId], landing on whichever channel it offers.
  ///
  /// The workspace is read from the controller rather than captured, because
  /// the rail that calls this is kept across rebuilds and may have been built
  /// against an older one.
  void _selectSpace(String spaceId) {
    final workspace = chatController.workspace;
    if (workspace == null) return;
    workspaceController.selectSpace(workspace, spaceId);
    final selected = workspaceController.selectedChannelId;
    if (selected != null) unawaited(chatController.openChannel(selected));
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
    if (channelId != null) _leaveFriendsPageFor(channelId);
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
    final workspace = chatController.workspace;
    if (workspace == null) return;
    final recipientId = await showDialog<String>(
      context: context,
      builder: (_) => DirectMessageDialog(
        people: DirectMessageCandidate.from(
          members: workspace.members,
          currentMemberId: workspace.currentMemberId,
          relationships:
              chatController.relationships?.relationships ?? const [],
        ),
      ),
    );
    if (recipientId == null || !context.mounted) return;
    await _openDirectConversation(context, recipientId);
  }

  /// Opens [userId]'s profile card beside [anchor]: a message author's name
  /// or avatar, a voice seat, or a friend's name.
  Future<void> _openMemberCard(
    BuildContext context,
    String spaceId,
    String userId,
    Rect anchor,
  ) async {
    final member = _memberOf(userId) ?? _friendAsMember(userId);
    if (member == null) return;
    await showProfileCard(
      context: context,
      anchor: anchor,
      builder: (close) =>
          _memberCard(context, member: member, spaceId: spaceId, close: close),
    );
  }

  /// The one profile card every surface opens for a member of [spaceId], or
  /// with [layout] the full profile window it opens. [close] closes it,
  /// before any action that leaves it.
  Widget _memberCard(
    BuildContext context, {
    required Member member,
    required String spaceId,
    required VoidCallback close,
    ProfileLayout layout = ProfileLayout.card,
  }) {
    final workspace = chatController.workspace!;
    final friends = friendsController;
    final isSelf = member.id == workspace.currentMemberId;
    final inServer = spaceId != CommunitySpace.directMessagesId;
    // Discord has no "report yourself", and blocking yourself is refused.
    final canReport = chatController.moderation != null && !isSelf;
    VoidCallback closing(Future<void> Function() action) => () {
      close();
      unawaited(action());
    };
    Widget card(
      Map<String, List<VoiceParticipantStateEvent>> seated,
    ) => MemberProfileCard(
      key: ValueKey(member.id),
      member: member,
      layout: layout,
      spaceId: inServer ? spaceId : null,
      workspace: workspace,
      friendsSince: switch (friends?.relationshipWith(member.id)) {
        final DiscordRelationship relationship
            when relationship.kind == DiscordRelationshipKind.friend =>
          relationship.since,
        _ => null,
      },
      voiceRoom: voiceRoomOf(
        member.id,
        workspace: workspace,
        seatedByChannel: seated,
      ),
      profile: memberProfileController,
      moderationBuilder: inServer
          ? () => _memberAdminController(spaceId, member.id)
          : null,
      onMessage: isSelf
          ? null
          : (text) {
              close();
              unawaited(
                _openDirectConversation(context, member.id, text: text),
              );
            },
      onAddFriend: friends != null && !isSelf && friends.canBefriend(member.id)
          ? () => unawaited(friends.befriend(member.id))
          : null,
      onReport: canReport
          ? closing(() => _reportMember(context, member))
          : null,
      onBlock: canReport ? closing(() => _blockMember(context, member)) : null,
      onOpenFullProfile: layout == ProfileLayout.card
          ? closing(
              () => showFullProfile(
                context: context,
                builder: (closeWindow) => _memberCard(
                  context,
                  member: member,
                  spaceId: spaceId,
                  close: closeWindow,
                  layout: ProfileLayout.window,
                ),
              ),
            )
          : null,
      onOpenProfile: (userId, anchor) =>
          unawaited(_openMemberCard(context, spaceId, userId, anchor)),
      onOpenServer: (serverId) {
        close();
        _selectSpace(serverId);
      },
      onJoinVoice: (channelId) {
        close();
        _openVoiceRoom(channelId);
      },
      onOpenLink: (uri) => unawaited(externalLinkLauncher.open(uri)),
    );
    // A member's "In voice" follows the seats.
    return _onSeats(
      (seated) => friends == null
          ? card(seated)
          : ListenableBuilder(
              listenable: friends,
              builder: (_, _) => card(seated),
            ),
    );
  }

  /// A friend who shares no server or DM with the account, as the
  /// relationship describes them. The workspace holds no record of them, and
  /// the card fetches the rest of their profile itself.
  Member? _friendAsMember(String userId) {
    final user = friendsController?.relationshipWith(userId)?.user;
    if (user == null) return null;
    return Member(
      id: user.id,
      displayName: user.displayName,
      username: user.username,
      initials: monogramOf(user.displayName),
      role: 'Discord user',
      presence: Presence.unknown,
      colorValue: monogramColorOf(user.id),
      avatarUrl: user.avatarUrl,
    );
  }

  /// Opens the DM with [recipientId] and sends [text] there, when given.
  ///
  /// The text is sent before the DM opens: a text Discord refuses goes into
  /// the DM's draft, which the box shows when it opens, so it can be sent
  /// again. A box already open would not read a draft written under it.
  Future<void> _openDirectConversation(
    BuildContext context,
    String recipientId, {
    String text = '',
  }) async {
    final channelId = await chatController.openDirectConversation(recipientId);
    if (!context.mounted) return;
    if (channelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Direct message could not be opened')),
      );
      return;
    }
    if (text.isNotEmpty &&
        !await chatController.sendMessage(channelId: channelId, body: text)) {
      final drafts = chatController.drafts;
      drafts.write(
        channelId,
        drafts.read(channelId).withFailedSend(ComposerDraft(text: text)),
      );
    }
    if (!context.mounted) return;
    final channel = chatController.workspace!.channelById(channelId);
    _openDestination(spaceId: channel.spaceId, channelId: channel.id);
  }
}

/// Calls [builder] again when the presence of any of [userIds] moves, for a
/// view that reads presences through the workspace.
class _WatchPresences extends StatelessWidget {
  const _WatchPresences({required this.userIds, required this.builder});

  final List<String> userIds;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    PresenceScope.watch(context, userIds);
    return builder(context);
  }
}
