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
        ),
      ),
    );
    if (channelId == null || !context.mounted) return;
    _openDestination(spaceId: space.id, channelId: channelId);
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
