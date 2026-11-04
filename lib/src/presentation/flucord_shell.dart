import 'dart:async';

import 'package:flutter/material.dart';

import '../application/channel_sidebar_order.dart';
import '../application/chat_controller.dart';
import '../application/connection_controller.dart';
import '../application/discord_oauth_controller.dart';
import '../application/friends_controller.dart';
import '../domain/direct_message_candidate.dart';
import '../application/guild_member_admin_controller.dart';
import '../application/guild_member_list_controller.dart';
import '../application/member_profile_controller.dart';
import '../application/guild_settings_controller.dart';
import '../application/inbox_catalog.dart';
import '../application/message_search_controller.dart';
import '../application/message_search_grammar.dart';
import '../application/oauth_guild_directory_controller.dart';
import '../application/oauth_guild_membership_controller.dart';
import '../application/quick_switcher_catalog.dart';
import '../application/voice_channel_surface.dart';
import '../application/workspace_controller.dart';
import '../application/self_video_controller.dart';
import '../application/voice_controller.dart';
import '../application/direct_call_controller.dart';
import '../domain/channel_capabilities.dart';
import '../domain/chat_models.dart';
import '../domain/discord_permissions.dart';
import '../domain/external_link_launcher.dart';
import '../domain/message_search.dart';
import '../domain/moderation_report.dart';
import '../domain/voice_connection.dart';
import '../domain/workspace_activity.dart';
import '../domain/workspace_permissions.dart';
import '../application/report_flow_controller.dart';
import 'conversation_pane.dart';
import 'shell_keyboard.dart';
import '../theme/flucord_radius.dart';
import '../theme/flucord_theme.dart';
import 'widgets/add_server_dialog.dart';
import 'widgets/cached_subtree.dart';
import 'widgets/channel_sidebar.dart';
import 'widgets/connection_banner.dart';
import 'widgets/connection_dialog.dart';
import 'widgets/destructive_confirmation.dart';
import 'widgets/discord_desktop_login_scope.dart';
import 'widgets/direct_message_views.dart';
import 'widgets/disconnected_workspace_view.dart';
import 'widgets/guild_event_form_dialog.dart';
import 'widgets/guild_scheduled_events_dialog.dart';
import 'widgets/guild_settings_dialog.dart';
import 'widgets/inbox_dialog.dart';
import 'widgets/incoming_call_overlay.dart';
import 'widgets/member_profile_popover.dart';
import 'widgets/member_sidebar.dart';
import 'widgets/message_search_panel.dart';
import 'widgets/navigation_theme.dart';
import 'widgets/notification_settings_menu.dart';
import 'widgets/oauth_guild_workspace.dart';
import 'widgets/pinned_messages_panel.dart';
import 'widgets/leave_server_dialog.dart';
import 'widgets/server_menu.dart';
import 'widgets/report_dialog.dart';
import 'widgets/server_rail.dart';
import 'widgets/status_views.dart';
import 'widgets/thread_browser_panel.dart';
import 'widgets/voice_connection_bar.dart';

part 'flucord_shell_navigation.dart';
part 'flucord_shell_conversation.dart';
part 'flucord_shell_canvas.dart';

/// The workspace chrome: the rail, the channel sidebar, the member and search
/// panels, and the conversation pane in the middle.
///
/// The controllers this widget lays out arrive as constructor parameters. The
/// conversation plane is different: the pane resolves its controllers from the
/// scope modules above this widget, so only navigation and panel intents cross
/// the boundary between the two.
/// Below this width the channel sidebar gives way to the rail alone.
///
/// It is under the smallest window at the largest zoom (940 / 1.4, less the
/// window frame), so the sidebar and the account panel show at every window
/// size the app allows.
const double _channelSidebarMinWidth = 640;
const double _railWidth = 72;
const double _channelSidebarWidth = 236;

/// The widest side panel, the search results.
const double _sidePanelMaxWidth = 340;

/// Below this width the composer's own buttons start to overlap.
const double _conversationMinWidth = 352;

class FlucordShell extends StatelessWidget {
  const FlucordShell({
    required this.chatController,
    required this.connectionController,
    required this.discordOAuthController,
    required this.oauthGuildDirectoryController,
    required this.oauthGuildMembershipController,
    required this.workspaceController,
    required this.themeMode,
    required this.onToggleTheme,
    required this.voiceController,
    required this.selfVideoController,
    required this.externalLinkLauncher,
    this.memberListController,
    this.memberProfileController,
    this.friendsController,
    this.messageSearchController,
    this.directCallController,
    super.key,
  });

  final ChatController chatController;
  final ConnectionController connectionController;
  final DiscordOAuthController discordOAuthController;
  final OAuthGuildDirectoryController oauthGuildDirectoryController;
  final OAuthGuildMembershipController oauthGuildMembershipController;
  final WorkspaceController workspaceController;

  /// Light or dark, as the app draws it, and the rail's switch between them.
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  final VoiceController voiceController;
  final SelfVideoController selfVideoController;
  final ExternalLinkLauncher externalLinkLauncher;

  /// Owns the member panel's roster subscription. Absent in hosts that never
  /// show the panel, such as the widget tests for a single pane.
  final GuildMemberListController? memberListController;

  /// Drives the full profile a member popover fetches. Absent in hosts that
  /// never open one, such as the widget tests for a single pane.
  final MemberProfileController? memberProfileController;

  /// The account's friend graph, or null on a transport that is never told
  /// one — the demo workspace and the bot session.
  final FriendsController? friendsController;

  /// Owns the server-side search and the page the results panel is showing.
  /// Absent in hosts that never offer it, such as the widget tests for a
  /// single pane.
  final MessageSearchController? messageSearchController;

  /// Owns calls in DMs and group DMs. Absent in hosts that cannot place one —
  /// the demo workspace, and every widget test that only drives a single pane.
  final DirectCallController? directCallController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: discordOAuthController,
      builder: (context, _) => ListenableBuilder(
        listenable: connectionController,
        builder: (context, _) => ListenableBuilder(
          listenable: chatController,
          builder: (context, _) => switch (chatController.state) {
            ChatLoadState.idle ||
            ChatLoadState.loading => const LoadingWorkspaceView(),
            // A connection attempt that failed is still cleaning up, and it
            // ends on the disconnected view, which says why.
            ChatLoadState.failure when connectionController.isBusy =>
              const LoadingWorkspaceView(),
            ChatLoadState.failure => FailedWorkspaceView(
              onRetry: chatController.load,
            ),
            ChatLoadState.ready => _buildWorkspace(
              context,
              chatController.workspace!,
            ),
          },
        ),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context, ChatWorkspace workspace) {
    if (workspace.spaces.isEmpty) return _buildEmptyWorkspace(context);
    final previousChannelId = workspaceController.selectedChannelId;
    workspaceController.reconcile(workspace);
    final landedChannelId = workspaceController.selectedChannelId;
    if (landedChannelId != null && landedChannelId != previousChannelId) {
      // The channel on screen went away, so the one in its place needs opening,
      // as a click would. That notifies, so it cannot run during this build.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(chatController.openChannel(landedChannelId)),
      );
    }
    return ListenableBuilder(
      listenable: connectionController,
      builder: (context, _) {
        return ListenableBuilder(
          listenable: workspaceController,
          builder: (context, _) {
            final spaceId = workspaceController.selectedSpaceId!;
            final channelId = workspaceController.selectedChannelId;
            final space = workspace.spaceById(spaceId);
            // One resolver for the whole frame: the sidebar asks about every
            // channel of the guild and the pane asks again about the open one,
            // and they must not answer differently.
            final permissions = WorkspacePermissions(workspace);
            final channels = permissions.visibleChannelsFor(spaceId);
            // Rolled up here rather than inside the rail so it can be compared
            // against the last frame's, which is what decides whether the rail
            // is redrawn at all.
            final activityBySpaceId = workspace.activityBySpace(
              readState: chatController.readState,
            );
            // Computed once per frame alongside the channel filter, from the
            // same resolver: the settings door and the buttons inside it must
            // not answer differently about the same account.
            final administration = permissions.administrationOf(spaceId);
            final canOpenSettings =
                !space.isDirectMessages && _canOpenSettings(administration);
            final canReport = chatController.moderation != null;

            /// Joining, creating and leaving need the guild-management plane;
            /// without it the rail hides its plus rather than opening a
            /// dialog whose every button would fail.
            final canManageServers = chatController.guildManagement != null;
            final channel = channelId == null
                ? null
                : workspace.channelById(channelId);
            return ShellKeyboard(
              workspace: workspace,
              channelId: channelId,
              onOpenDestination: _openQuickSwitcherDestination,
              onStep: _takeStep,
              onOpenChannel: _openChannelFromHistory,
              child: Scaffold(
                body: _withWorkspaceChrome(
                  workspace,
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final showChannels =
                          constraints.maxWidth >= _channelSidebarMinWidth;
                      final membersFit = constraints.maxWidth >= 1120;
                      final threadParentId = channel?.threadParentId;
                      final allowThreadPanel =
                          channel?.kind == ChannelKind.text &&
                          channel?.isDirectMessage == false &&
                          threadParentId != null;
                      final voiceSurface = channel == null
                          ? VoiceChannelSurface.room
                          : workspaceController.voiceSurfaceOf(channel.id);
                      final showsMessages =
                          channel != null &&
                          showsMessageTimeline(channel, voiceSurface);
                      final searchController = messageSearchController;
                      final showThreads =
                          workspaceController.showThreads && allowThreadPanel;
                      final showSearchPanel =
                          workspaceController.showSearch &&
                          searchController != null &&
                          !showThreads;
                      final showPins =
                          workspaceController.showPins &&
                          showsMessages &&
                          !showThreads &&
                          !showSearchPanel;
                      final showMembers =
                          membersFit &&
                          (!space.isDirectMessages ||
                              (channel?.isDirectMessage ?? false)) &&
                          workspaceController.showMembers &&
                          !showPins &&
                          !showThreads &&
                          !showSearchPanel;
                      // Asking the server about a conversation the account may
                      // not read the history of is a request Discord answers
                      // with a rejection, so the affordance is withheld instead.
                      final canSearch =
                          channel != null &&
                          (searchController?.isSupported ?? false) &&
                          permissions.can(
                            DiscordPermissions.readMessageHistory,
                            channel,
                          );
                      final Widget? sidePanel = showSearchPanel
                          ? MessageSearchPanel(
                              controller: searchController,
                              workspace: workspace,
                              linkLauncher: externalLinkLauncher,
                              channels: [
                                if (channel != null)
                                  ..._searchChannels(workspace, space, channel),
                              ],
                              query: workspaceController.query,
                              onSubmitQuery: channel != null && canSearch
                                  ? (text) {
                                      // The bar echoes the line the controls
                                      // composed, exactly as a typed line.
                                      workspaceController.setQuery(text);
                                      _submitSearch(
                                        workspace,
                                        space,
                                        channel,
                                        text,
                                      );
                                    }
                                  : null,
                              onClose: () {
                                workspaceController.closeSearch();
                                searchController.clear();
                              },
                              onJump: (channelId, messageId) =>
                                  _openDestination(
                                    spaceId:
                                        workspace
                                            .channelOrNull(channelId)
                                            ?.spaceId ??
                                        spaceId,
                                    channelId: channelId,
                                    messageId: messageId,
                                    voiceSurface: VoiceChannelSurface.chat,
                                  ),
                              onSelectChannel: (id) => _selectChannel(
                                id,
                                voiceSurface: VoiceChannelSurface.chat,
                              ),
                            )
                          : showPins
                          ? PinnedMessagesPanel(
                              workspace: workspace,
                              linkLauncher: externalLinkLauncher,
                              onSelectChannel: (id) => _selectChannel(
                                id,
                                voiceSurface: VoiceChannelSurface.chat,
                              ),
                              channelId: channel.id,
                              history: chatController.pinnedMessages(
                                channel.id,
                              ),
                              isLoading: chatController.isLoadingPins(
                                channel.id,
                              ),
                              error: chatController.pinError(channel.id),
                              onClose: workspaceController.togglePins,
                              onRefresh: () => unawaited(
                                chatController.loadPinnedMessages(
                                  channel.id,
                                  refresh: true,
                                ),
                              ),
                              onUnpin: chatController.togglePin,
                            )
                          : showThreads
                          ? ThreadBrowserPanel(
                              parentChannel: workspace.channelById(
                                threadParentId,
                              ),
                              activeThreads: channels
                                  .where(
                                    (item) =>
                                        item.isThread &&
                                        !item.isArchived &&
                                        item.parentId == threadParentId,
                                  )
                                  .toList(growable: false),
                              archivedThreads: chatController
                                  .archivedThreadsFor(threadParentId),
                              isLoading: chatController
                                  .isLoadingArchivedThreads(threadParentId),
                              error: chatController.archivedThreadsError(
                                threadParentId,
                              ),
                              canLoadMore: chatController
                                  .canLoadMoreArchivedThreads(threadParentId),
                              onClose: workspaceController.toggleThreads,
                              onRefresh: () => unawaited(
                                chatController.loadArchivedThreads(
                                  threadParentId,
                                  refresh: true,
                                ),
                              ),
                              onLoadMore: () => unawaited(
                                chatController.loadArchivedThreads(
                                  threadParentId,
                                ),
                              ),
                              onSelectThread: _selectChannel,
                            )
                          : null;
                      // A panel that would squeeze the conversation below what
                      // the composer needs takes its place until it is closed.
                      // The conversation stays mounted, so its text is kept.
                      final panelCovers =
                          sidePanel != null &&
                          constraints.maxWidth -
                                  _railWidth -
                                  (showChannels ? _channelSidebarWidth : 0) -
                                  FlucordTheme.canvasInset -
                                  _sidePanelMaxWidth <
                              _conversationMinWidth;
                      return Row(
                        children: [
                          // Kept across rebuilds that leave every pip where it
                          // was, which is most of them: an arriving message moves
                          // a space's activity only when it changes what is
                          // waiting there. Everything the rail draws is listed
                          // below, and it opens a space from the workspace as it
                          // stands when pressed rather than the one it was built
                          // with.
                          CachedSubtree(
                            dependencies: [
                              workspace.spaces,
                              activityBySpaceId,
                              spaceId,
                              connectionController.mode,
                              themeMode,
                            ],
                            builder: (_) => NavigationTheme(
                              child: ServerRail(
                                spaces: workspace.spaces,
                                activity: activityBySpaceId,
                                selectedSpaceId: spaceId,
                                onSelectSpace: _selectSpace,
                                onToggleTheme: onToggleTheme,
                                onOpenConnections: () =>
                                    _openConnections(context),
                                onAddServer: canManageServers
                                    ? () => unawaited(_addServer(context))
                                    : null,
                                onOpenSpaceMenu: (spaceId, position) =>
                                    unawaited(
                                      _openSpaceMenu(
                                        context,
                                        spaceId,
                                        position,
                                      ),
                                    ),
                                sessionMode: connectionController.mode,
                                isDark: themeMode == ThemeMode.dark,
                              ),
                            ),
                          ),
                          if (showChannels)
                            // Rebuilt from the voice controller: who is
                            // sitting in a voice channel changes without
                            // anything else in the shell changing, and
                            // the seats used to appear only once some
                            // unrelated event redrew the sidebar.
                            ListenableBuilder(
                              listenable: voiceController,
                              builder: (_, _) {
                                final seats = voiceController.seatedByChannel;
                                final speaking = {
                                  for (final participant
                                      in voiceController.participants)
                                    if (participant.isSpeaking)
                                      participant.userId,
                                };
                                final categories = workspace.categoriesFor(
                                  spaceId,
                                );
                                final currentMember = workspace.memberById(
                                  workspace.currentMemberId,
                                );
                                return CachedSubtree(
                                  dependencies: [
                                    space,
                                    channels,
                                    categories,
                                    currentMember,
                                    _shownMembers(
                                      workspace,
                                      channels: channels,
                                      seats: seats,
                                    ),
                                    seats,
                                    speaking,
                                    channelId,
                                    workspaceController.collapsedCategoryIds,
                                    // Not the whole snapshot: each ack makes a new
                                    // one, and the sidebar reads only these.
                                    chatController.readState.settings,
                                    chatController
                                        .readState
                                        .accountNotificationFlags,
                                    connectionController.mode,
                                    chatController.connectionStatus,
                                    canOpenSettings,
                                    chatController
                                        .scheduledEventsFor(spaceId)
                                        .length,
                                    chatController.isLoadingScheduledEvents(
                                      spaceId,
                                    ),
                                    chatController.scheduledEventsError(
                                      spaceId,
                                    ),
                                  ],
                                  builder: (_) => NavigationTheme(
                                    child: ChannelSidebar(
                                      space: space,
                                      friends: friendsController,
                                      categories: categories,
                                      currentMember: currentMember,
                                      memberOf: _memberOf,
                                      channelOf: _channelOf,
                                      seatedByChannel: seats,
                                      speakingUserIds: speaking,
                                      // Discord opens a profile from these rows with
                                      // either mouse button. Ours were labels.
                                      onOpenMemberProfile: (userId) =>
                                          unawaited(
                                            _openMemberCard(
                                              context,
                                              spaceId,
                                              userId,
                                            ),
                                          ),
                                      // A voice connection outlives the room view, so
                                      // leaving it has to stay reachable from wherever
                                      // the user has navigated to since.
                                      voiceConnectionBar: VoiceConnectionBar(
                                        controller: voiceController,
                                        camera: selfVideoController,
                                        channelNameFor: (id) =>
                                            _channelOf(id)?.name,
                                        serverNameFor: _serverNameOf,
                                        onOpenChannel: _openVoiceRoom,
                                      ),
                                      channels: channels,
                                      selectedChannelId: channelId,
                                      collapsedCategoryIds: workspaceController
                                          .collapsedCategoryIds,
                                      onToggleCategory:
                                          workspaceController.toggleCategory,
                                      onNewDirectMessage: () =>
                                          _openDirectMessage(context),
                                      onAcceptMessageRequest: (channelId) =>
                                          unawaited(
                                            chatController.acceptMessageRequest(
                                              channelId,
                                            ),
                                          ),
                                      onDeclineMessageRequest: (channelId) =>
                                          unawaited(
                                            chatController
                                                .declineMessageRequest(
                                                  channelId,
                                                ),
                                          ),
                                      scheduledEventCount: chatController
                                          .scheduledEventsFor(space.id)
                                          .length,
                                      isLoadingScheduledEvents: chatController
                                          .isLoadingScheduledEvents(space.id),
                                      scheduledEventsError: chatController
                                          .scheduledEventsError(space.id),
                                      onOpenEvents: () =>
                                          _openScheduledEvents(context, space),
                                      onOpenServerSettings: canOpenSettings
                                          ? () => unawaited(
                                              _openGuildSettings(
                                                context,
                                                space,
                                                administration,
                                              ),
                                            )
                                          : null,
                                      onLeaveServer: canManageServers
                                          ? () => unawaited(
                                              _leaveServer(context, space),
                                            )
                                          : null,
                                      onReportServer: () => unawaited(
                                        _reportSpace(context, space),
                                      ),
                                      onSelectChannel: _selectChannel,
                                      readState: chatController.readState,
                                      onNotificationRequest:
                                          (request, target) =>
                                              _applyNotificationRequest(
                                                request,
                                                space: space,
                                                channel: target,
                                              ),
                                      sessionMode: connectionController.mode,
                                      connectionStatus:
                                          chatController.connectionStatus,
                                    ),
                                  ),
                                );
                              },
                            ),
                          Expanded(
                            child: _CanvasCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Offstage(
                                          offstage: panelCovers,
                                          child: channel == null
                                              ? DirectMessagesEmptyView(
                                                  onNewMessage: () =>
                                                      _openDirectMessage(
                                                        context,
                                                      ),
                                                )
                                              : _conversationPane(
                                                  context: context,
                                                  workspace: workspace,
                                                  capabilities: permissions
                                                      .capabilitiesIn(channel),
                                                  channel: channel,
                                                  channels: channels,
                                                  space: space,
                                                  showChannels: showChannels,
                                                  membersFit: membersFit,
                                                  showMembers: showMembers,
                                                  showPins: showPins,
                                                  showThreads: showThreads,
                                                  allowThreadPanel:
                                                      allowThreadPanel,
                                                  canSearch: canSearch,
                                                ),
                                        ),
                                        if (panelCovers) sidePanel,
                                      ],
                                    ),
                                  ),
                                  if (sidePanel != null && !panelCovers)
                                    sidePanel,
                                  if (showMembers && space.isDirectMessages)
                                    if (_recipientOf(workspace, channel)
                                        case final person?)
                                      MemberProfilePanel(
                                        person: person,
                                        spaces: workspace.spaces,
                                      )
                                    else
                                      const SizedBox.shrink()
                                  else if (showMembers)
                                    // A member's "In voice" line follows the
                                    // seats. Only the seats: the controller
                                    // also fires on every speaking change.
                                    ListenableBuilder(
                                      listenable: voiceController.seats,
                                      builder: (_, _) => MemberSidebar(
                                        seatedByChannel:
                                            voiceController.seatedByChannel,
                                        heldRolesOf: (member) => workspace
                                            .heldRolesOf(member, spaceId),
                                        members: workspace.members,
                                        spaceId: spaceId,
                                        channelId: channel?.id,
                                        memberList: memberListController,
                                        roles: workspace.roles,
                                        profile: memberProfileController,
                                        currentMemberId:
                                            workspace.currentMemberId,
                                        onMessage: (member) => unawaited(
                                          _openDirectConversation(
                                            context,
                                            member.id,
                                          ),
                                        ),
                                        onReport: canReport
                                            ? (member) => unawaited(
                                                _reportMember(context, member),
                                              )
                                            : null,
                                        onBlock: canReport
                                            ? (member) => unawaited(
                                                _blockMember(context, member),
                                              )
                                            : null,
                                        moderationBuilder: (member) =>
                                            _memberAdminController(
                                              spaceId,
                                              member.id,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
