import 'dart:async';

import 'package:flutter/material.dart';

import '../application/chat_controller.dart';
import '../application/composer_autocomplete_catalog.dart';
import '../application/connection_controller.dart';
import '../application/direct_call_controller.dart';
import '../application/discord_oauth_controller.dart';
import '../application/guild_member_list_controller.dart';
import '../application/inbox_catalog.dart';
import '../application/oauth_guild_directory_controller.dart';
import '../application/oauth_guild_membership_controller.dart';
import '../application/quick_switcher_catalog.dart';
import '../application/voice_channel_surface.dart';
import '../application/workspace_controller.dart';
import '../application/voice_controller.dart';
import '../domain/channel_capabilities.dart';
import '../domain/chat_models.dart';
import '../domain/attachment_download.dart';
import '../domain/external_link_launcher.dart';
import '../domain/voice_message_recorder.dart';
import '../domain/workspace_permissions.dart';
import 'widgets/channel_sidebar.dart';
import 'widgets/chat_header.dart';
import 'widgets/connection_dialog.dart';
import 'widgets/discord_desktop_login_scope.dart';
import 'widgets/create_forum_post_dialog.dart';
import 'widgets/create_poll_dialog.dart';
import 'widgets/direct_message_views.dart';
import 'widgets/forum_channel_view.dart';
import 'widgets/guild_scheduled_events_dialog.dart';
import 'widgets/inbox_dialog.dart';
import 'widgets/incoming_call_overlay.dart';
import 'widgets/member_sidebar.dart';
import 'widgets/message_composer.dart';
import 'widgets/message_forward_dialog.dart';
import 'widgets/message_list.dart';
import 'widgets/oauth_guild_workspace.dart';
import 'widgets/pinned_messages_panel.dart';
import 'widgets/quick_switcher.dart';
import 'widgets/reaction_details_dialog.dart';
import 'widgets/server_rail.dart';
import 'widgets/status_views.dart';
import 'widgets/thread_browser_panel.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/voice_room_view.dart';

part 'flucord_shell_navigation.dart';
part 'flucord_conversation_pane.dart';
part 'flucord_shell_conversation.dart';

class FlucordShell extends StatelessWidget {
  const FlucordShell({
    required this.chatController,
    required this.connectionController,
    required this.discordOAuthController,
    required this.oauthGuildDirectoryController,
    required this.oauthGuildMembershipController,
    required this.workspaceController,
    required this.voiceController,
    required this.voiceMessageRecorder,
    required this.attachmentDownloadService,
    required this.externalLinkLauncher,
    this.memberListController,
    this.directCallController,
    super.key,
  });

  final ChatController chatController;
  final ConnectionController connectionController;
  final DiscordOAuthController discordOAuthController;
  final OAuthGuildDirectoryController oauthGuildDirectoryController;
  final OAuthGuildMembershipController oauthGuildMembershipController;
  final WorkspaceController workspaceController;
  final VoiceController voiceController;
  final VoiceMessageRecorder? voiceMessageRecorder;
  final AttachmentDownloadService attachmentDownloadService;
  final ExternalLinkLauncher externalLinkLauncher;

  /// Owns the member panel's roster subscription. Absent in hosts that never
  /// show the panel, such as the widget tests for a single pane.
  final GuildMemberListController? memberListController;

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
    workspaceController.reconcile(workspace);
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
            final channel = channelId == null
                ? null
                : workspace.channelById(channelId);
            final inboxSummary = InboxCatalog.fromWorkspace(workspace).summary;
            return Scaffold(
              body: _withIncomingCall(
                workspace,
                LayoutBuilder(
                  builder: (context, constraints) {
                    final showChannels = constraints.maxWidth >= 760;
                    final membersFit = constraints.maxWidth >= 1120;
                    final threadParentId = channel == null
                        ? null
                        : channel.isThread
                        ? channel.parentId
                        : channel.id;
                    final allowThreadPanel =
                        channel?.kind == ChannelKind.text &&
                        channel?.isDirectMessage == false &&
                        threadParentId != null;
                    final voiceSurface = channel == null
                        ? VoiceChannelSurface.room
                        : workspaceController.voiceSurfaceOf(channel.id);
                    final showsMessages =
                        channel != null &&
                        _showsMessageTimeline(channel, voiceSurface);
                    final showThreads =
                        workspaceController.showThreads && allowThreadPanel;
                    final showPins =
                        workspaceController.showPins &&
                        showsMessages &&
                        !showThreads;
                    final showMembers =
                        membersFit &&
                        !space.isDirectMessages &&
                        workspaceController.showMembers &&
                        !showPins &&
                        !showThreads;
                    return Row(
                      children: [
                        ServerRail(
                          workspace: workspace,
                          selectedSpaceId: spaceId,
                          onSelectSpace: (id) {
                            workspaceController.selectSpace(workspace, id);
                            final selected =
                                workspaceController.selectedChannelId;
                            if (selected != null) {
                              chatController.openChannel(selected);
                            }
                          },
                          onToggleTheme: workspaceController.toggleTheme,
                          onOpenConnections: () => _openConnections(context),
                          sessionMode: connectionController.mode,
                          isDark:
                              workspaceController.themeMode == ThemeMode.dark,
                        ),
                        if (showChannels)
                          ChannelSidebar(
                            space: space,
                            channels: channels,
                            selectedChannelId: channelId,
                            workspace: workspace,
                            collapsedCategoryIds:
                                workspaceController.collapsedCategoryIds,
                            onToggleCategory:
                                workspaceController.toggleCategory,
                            onNewDirectMessage: () =>
                                _openDirectMessage(context),
                            scheduledEventCount: chatController
                                .scheduledEventsFor(space.id)
                                .length,
                            isLoadingScheduledEvents: chatController
                                .isLoadingScheduledEvents(space.id),
                            scheduledEventsError: chatController
                                .scheduledEventsError(space.id),
                            onOpenEvents: () =>
                                _openScheduledEvents(context, space),
                            onSelectChannel: _selectChannel,
                            sessionMode: connectionController.mode,
                            connectionStatus: chatController.connectionStatus,
                          ),
                        Expanded(
                          child: channel == null
                              ? DirectMessagesEmptyView(
                                  onNewMessage: () =>
                                      _openDirectMessage(context),
                                )
                              : _conversationPane(
                                  context: context,
                                  workspace: workspace,
                                  capabilities: permissions.capabilitiesIn(
                                    channel,
                                  ),
                                  channel: channel,
                                  channels: channels,
                                  space: space,
                                  showChannels: showChannels,
                                  membersFit: membersFit,
                                  showMembers: showMembers,
                                  showPins: showPins,
                                  showThreads: showThreads,
                                  threadParentId: threadParentId,
                                  allowThreadPanel: allowThreadPanel,
                                  voiceSurface: voiceSurface,
                                  inboxSummary: inboxSummary,
                                ),
                        ),
                        if (showPins)
                          PinnedMessagesPanel(
                            workspace: workspace,
                            linkLauncher: externalLinkLauncher,
                            onSelectChannel: (id) => _selectChannel(
                              id,
                              voiceSurface: VoiceChannelSurface.chat,
                            ),
                            channelId: channel.id,
                            history: chatController.pinnedMessages(channel.id),
                            isLoading: chatController.isLoadingPins(channel.id),
                            error: chatController.pinError(channel.id),
                            onClose: workspaceController.togglePins,
                            onRefresh: () => unawaited(
                              chatController.loadPinnedMessages(
                                channel.id,
                                refresh: true,
                              ),
                            ),
                            onUnpin: chatController.togglePin,
                          ),
                        if (showThreads)
                          ThreadBrowserPanel(
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
                            archivedThreads: chatController.archivedThreadsFor(
                              threadParentId,
                            ),
                            isLoading: chatController.isLoadingArchivedThreads(
                              threadParentId,
                            ),
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
                          ),
                        if (showMembers)
                          MemberSidebar(
                            members: workspace.members,
                            spaceId: spaceId,
                            channelId: channel?.id,
                            memberList: memberListController,
                            roles: workspace.roles,
                            currentMemberId: workspace.currentMemberId,
                            onMessage: (member) => unawaited(
                              _openDirectConversation(context, member.id),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ).withQuickSwitcher(
              workspace: workspace,
              onSelected: _openQuickSwitcherDestination,
            );
          },
        );
      },
    );
  }
}
