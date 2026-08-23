part of 'flucord_shell.dart';

extension _FlucordShellConversation on FlucordShell {
  /// Builds the pane for the selected channel.
  ///
  /// The pane resolves its own controllers from the scopes above the shell,
  /// so this only hands over what varies: the channel, the workspace data,
  /// the layout facts, and the navigation intents.
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
    required bool allowThreadPanel,
    required bool canSearch,
  }) => ConversationPane(
    workspace: workspace,
    capabilities: capabilities,
    channel: channel,
    channels: channels,
    compact: !showChannels,
    allowMemberPanel: membersFit && !space.isDirectMessages,
    allowThreadPanel: allowThreadPanel,
    showMembers: showMembers,
    showPins: showPins,
    showThreads: showThreads,
    onPickChannel: _selectChannel,
    onSelectChannel: (id) =>
        _selectChannel(id, voiceSurface: VoiceChannelSurface.chat),
    onSubmitQuery: canSearch
        ? (text) => _submitSearch(workspace, space, channel, text)
        : null,
    onOpenInbox: () => _openInbox(context),
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
