import 'dart:async';

import 'package:flutter/material.dart';

import '../application/chat_controller.dart';
import '../application/connection_controller.dart';
import '../application/inbox_catalog.dart';
import '../application/quick_switcher_catalog.dart';
import '../application/workspace_controller.dart';
import '../application/voice_controller.dart';
import '../domain/chat_models.dart';
import '../domain/external_link_launcher.dart';
import 'widgets/channel_sidebar.dart';
import 'widgets/chat_header.dart';
import 'widgets/connection_dialog.dart';
import 'widgets/create_forum_post_dialog.dart';
import 'widgets/direct_message_views.dart';
import 'widgets/forum_channel_view.dart';
import 'widgets/inbox_dialog.dart';
import 'widgets/member_sidebar.dart';
import 'widgets/message_composer.dart';
import 'widgets/message_list.dart';
import 'widgets/pinned_messages_panel.dart';
import 'widgets/quick_switcher.dart';
import 'widgets/server_rail.dart';
import 'widgets/status_views.dart';
import 'widgets/thread_browser_panel.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/voice_room_view.dart';

part 'flucord_shell_navigation.dart';
part 'flucord_conversation_pane.dart';

class FlucordShell extends StatelessWidget {
  const FlucordShell({
    required this.chatController,
    required this.connectionController,
    required this.workspaceController,
    required this.voiceController,
    required this.externalLinkLauncher,
    super.key,
  });

  final ChatController chatController;
  final ConnectionController connectionController;
  final WorkspaceController workspaceController;
  final VoiceController voiceController;
  final ExternalLinkLauncher externalLinkLauncher;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chatController,
      builder: (context, _) {
        return switch (chatController.state) {
          ChatLoadState.idle ||
          ChatLoadState.loading => const LoadingWorkspaceView(),
          ChatLoadState.failure => FailedWorkspaceView(
            onRetry: chatController.load,
          ),
          ChatLoadState.ready => _buildWorkspace(
            context,
            chatController.workspace!,
          ),
        };
      },
    );
  }

  Widget _buildWorkspace(BuildContext context, ChatWorkspace workspace) {
    if (workspace.spaces.isEmpty) {
      return EmptyWorkspaceView(
        onOpenConnections: () => _openConnections(context),
      );
    }
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
            final channels = workspace.channelsFor(spaceId);
            final channel = channelId == null
                ? null
                : workspace.channelById(channelId);
            final inboxSummary = InboxCatalog.fromWorkspace(workspace).summary;
            return Scaffold(
              body: LayoutBuilder(
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
                  final showThreads =
                      workspaceController.showThreads && allowThreadPanel;
                  final showPins =
                      workspaceController.showPins &&
                      channel?.kind == ChannelKind.text &&
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
                        isDark: workspaceController.themeMode == ThemeMode.dark,
                      ),
                      if (showChannels)
                        ChannelSidebar(
                          space: space,
                          channels: channels,
                          selectedChannelId: channelId,
                          workspace: workspace,
                          collapsedCategoryIds:
                              workspaceController.collapsedCategoryIds,
                          onToggleCategory: workspaceController.toggleCategory,
                          onNewDirectMessage: () => _openDirectMessage(context),
                          onSelectChannel: (id) {
                            workspaceController.selectChannel(id);
                            chatController.openChannel(id);
                          },
                          sessionMode: connectionController.mode,
                          connectionStatus: chatController.connectionStatus,
                        ),
                      Expanded(
                        child: channel == null
                            ? DirectMessagesEmptyView(
                                onNewMessage: () => _openDirectMessage(context),
                              )
                            : _ConversationPane(
                                workspace: workspace,
                                externalLinkLauncher: externalLinkLauncher,
                                channel: channel,
                                channels: channels,
                                query: workspaceController.query,
                                targetMessageId:
                                    workspaceController.targetMessageId,
                                compact: !showChannels,
                                allowMemberPanel:
                                    membersFit && !space.isDirectMessages,
                                allowThreadPanel: allowThreadPanel,
                                showMembers: showMembers,
                                showPins: showPins,
                                showThreads: showThreads,
                                forumArchivedPosts:
                                    channel.kind == ChannelKind.forum ||
                                        channel.kind == ChannelKind.media
                                    ? chatController.archivedThreadsFor(
                                        channel.id,
                                      )
                                    : const [],
                                isLoadingForumPosts: chatController
                                    .isLoadingArchivedThreads(channel.id),
                                forumPostsError: chatController
                                    .archivedThreadsError(channel.id),
                                canLoadMoreForumPosts: chatController
                                    .canLoadMoreArchivedThreads(channel.id),
                                inboxSummary: inboxSummary,
                                typingMembers: chatController.typingMembersFor(
                                  channel.id,
                                ),
                                isSending: chatController.isSending,
                                isLoading: chatController.isChannelLoading(
                                  channel.id,
                                ),
                                loadError: chatController.channelError(
                                  channel.id,
                                ),
                                canLoadOlder: chatController
                                    .canLoadOlderMessages(channel.id),
                                isLoadingOlder: chatController
                                    .isLoadingOlderMessages(channel.id),
                                olderLoadError: chatController
                                    .olderMessagesError(channel.id),
                                onLoadOlder: () => unawaited(
                                  chatController.loadOlderMessages(channel.id),
                                ),
                                onRetry: () => chatController.openChannel(
                                  channel.id,
                                  refresh: true,
                                ),
                                onSelectChannel: (id) {
                                  workspaceController.selectChannel(id);
                                  chatController.openChannel(id);
                                },
                                onQueryChanged: workspaceController.setQuery,
                                onToggleMembers:
                                    workspaceController.toggleMembers,
                                onTogglePins: () {
                                  workspaceController.togglePins();
                                  if (workspaceController.showPins) {
                                    unawaited(
                                      chatController.loadPinnedMessages(
                                        channel.id,
                                      ),
                                    );
                                  }
                                },
                                onToggleThreads: () {
                                  workspaceController.toggleThreads();
                                  if (workspaceController.showThreads &&
                                      threadParentId != null) {
                                    unawaited(
                                      chatController.loadArchivedThreads(
                                        threadParentId,
                                      ),
                                    );
                                  }
                                },
                                onRefreshForumPosts: () => unawaited(
                                  chatController.loadArchivedThreads(
                                    channel.id,
                                    refresh: true,
                                  ),
                                ),
                                onLoadMoreForumPosts: () => unawaited(
                                  chatController.loadArchivedThreads(
                                    channel.id,
                                  ),
                                ),
                                onLoadForumPostPreview: (postId) => unawaited(
                                  chatController.loadForumPostPreview(postId),
                                ),
                                onCreateForumPost:
                                    (
                                      name,
                                      content,
                                      attachments,
                                      duration,
                                      tagIds,
                                    ) async {
                                      final thread = await chatController
                                          .createForumPost(
                                            channelId: channel.id,
                                            name: name,
                                            content: content,
                                            autoArchiveDurationMinutes:
                                                duration,
                                            attachments: attachments,
                                            appliedTagIds: tagIds,
                                          );
                                      if (thread == null) return false;
                                      workspaceController.selectChannel(
                                        thread.id,
                                      );
                                      unawaited(
                                        chatController.openChannel(thread.id),
                                      );
                                      return true;
                                    },
                                onOpenInbox: () => _openInbox(context),
                                onSend: (body, attachments, replyToMessageId) =>
                                    chatController.sendMessage(
                                      channelId: channel.id,
                                      body: body,
                                      attachments: attachments,
                                      replyToMessageId: replyToMessageId,
                                    ),
                                onEdit: chatController.editMessage,
                                onDelete: chatController.deleteMessage,
                                onToggleReaction: chatController.toggleReaction,
                                onAddReaction: chatController.addReaction,
                                onCreateThread:
                                    (message, name, duration) async {
                                      final thread = await chatController
                                          .createThreadFromMessage(
                                            message,
                                            name: name,
                                            autoArchiveDurationMinutes:
                                                duration,
                                          );
                                      if (thread == null) return false;
                                      workspaceController.selectChannel(
                                        thread.id,
                                      );
                                      unawaited(
                                        chatController.openChannel(thread.id),
                                      );
                                      return true;
                                    },
                                onTogglePin: chatController.togglePin,
                                onTyping: () =>
                                    chatController.startTyping(channel.id),
                                voiceController: voiceController,
                              ),
                      ),
                      if (showPins && channel != null)
                        PinnedMessagesPanel(
                          workspace: workspace,
                          linkLauncher: externalLinkLauncher,
                          onSelectChannel: (id) {
                            workspaceController.selectChannel(id);
                            chatController.openChannel(id);
                          },
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
                          parentChannel: workspace.channelById(threadParentId),
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
                            chatController.loadArchivedThreads(threadParentId),
                          ),
                          onSelectThread: (id) {
                            workspaceController.selectChannel(id);
                            unawaited(chatController.openChannel(id));
                          },
                        ),
                      if (showMembers)
                        MemberSidebar(
                          members: workspace.members,
                          spaceId: spaceId,
                          currentMemberId: workspace.currentMemberId,
                          onMessage: (member) => unawaited(
                            _openDirectConversation(context, member.id),
                          ),
                        ),
                    ],
                  );
                },
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
