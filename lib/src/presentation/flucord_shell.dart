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
import 'widgets/direct_message_views.dart';
import 'widgets/inbox_dialog.dart';
import 'widgets/member_sidebar.dart';
import 'widgets/message_composer.dart';
import 'widgets/message_list.dart';
import 'widgets/pinned_messages_panel.dart';
import 'widgets/quick_switcher.dart';
import 'widgets/server_rail.dart';
import 'widgets/status_views.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/voice_room_view.dart';

part 'flucord_shell_navigation.dart';

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
                  final showPins =
                      workspaceController.showPins &&
                      channel?.kind == ChannelKind.text;
                  final showMembers =
                      membersFit &&
                      !space.isDirectMessages &&
                      workspaceController.showMembers &&
                      !showPins;
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
                                showMembers: showMembers,
                                showPins: showPins,
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

class _ConversationPane extends StatefulWidget {
  const _ConversationPane({
    required this.workspace,
    required this.externalLinkLauncher,
    required this.channel,
    required this.channels,
    required this.query,
    required this.targetMessageId,
    required this.compact,
    required this.allowMemberPanel,
    required this.showMembers,
    required this.showPins,
    required this.inboxSummary,
    required this.typingMembers,
    required this.isSending,
    required this.isLoading,
    required this.loadError,
    required this.canLoadOlder,
    required this.isLoadingOlder,
    required this.olderLoadError,
    required this.onLoadOlder,
    required this.onRetry,
    required this.onSelectChannel,
    required this.onQueryChanged,
    required this.onToggleMembers,
    required this.onTogglePins,
    required this.onOpenInbox,
    required this.onSend,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReaction,
    required this.onAddReaction,
    required this.onCreateThread,
    required this.onTogglePin,
    required this.onTyping,
    required this.voiceController,
  });

  final ChatWorkspace workspace;
  final ExternalLinkLauncher externalLinkLauncher;
  final ConversationChannel channel;
  final List<ConversationChannel> channels;
  final String query;
  final String? targetMessageId;
  final bool compact;
  final bool allowMemberPanel;
  final bool showMembers;
  final bool showPins;
  final InboxSummary inboxSummary;
  final List<Member> typingMembers;
  final bool isSending;
  final bool isLoading;
  final Object? loadError;
  final bool canLoadOlder;
  final bool isLoadingOlder;
  final Object? olderLoadError;
  final VoidCallback onLoadOlder;
  final VoidCallback onRetry;
  final ValueChanged<String> onSelectChannel;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleMembers;
  final VoidCallback onTogglePins;
  final VoidCallback onOpenInbox;
  final SendMessageCallback onSend;
  final Future<bool> Function(ChatMessage, String) onEdit;
  final Future<void> Function(ChatMessage) onDelete;
  final Future<void> Function(ChatMessage, MessageReaction) onToggleReaction;
  final Future<void> Function(ChatMessage, String) onAddReaction;
  final Future<bool> Function(ChatMessage, String, int) onCreateThread;
  final Future<void> Function(ChatMessage) onTogglePin;
  final VoidCallback onTyping;
  final VoiceController voiceController;

  @override
  State<_ConversationPane> createState() => _ConversationPaneState();
}

class _ConversationPaneState extends State<_ConversationPane> {
  ChatMessage? _replyTo;

  @override
  void didUpdateWidget(covariant _ConversationPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) _replyTo = null;
  }

  @override
  Widget build(BuildContext context) {
    final conversation = switch (widget.channel.kind) {
      ChannelKind.voice => VoiceRoomView(
        guildId: widget.channel.spaceId,
        channelId: widget.channel.id,
        channelName: widget.channel.name,
        controller: widget.voiceController,
        members: widget.workspace.members,
        currentMemberId: widget.workspace.currentMemberId,
      ),
      ChannelKind.text when widget.isLoading => const ChannelLoadingView(),
      ChannelKind.text when widget.loadError != null => ChannelFailureView(
        onRetry: widget.onRetry,
      ),
      ChannelKind.text => MessageList(
        workspace: widget.workspace,
        externalLinkLauncher: widget.externalLinkLauncher,
        channel: widget.channel,
        query: widget.query,
        targetMessageId: widget.targetMessageId,
        onReply: (message) => setState(() => _replyTo = message),
        onEdit: widget.onEdit,
        onDelete: widget.onDelete,
        onToggleReaction: widget.onToggleReaction,
        onAddReaction: widget.onAddReaction,
        onCreateThread: widget.onCreateThread,
        onTogglePin: widget.onTogglePin,
        canLoadOlder: widget.canLoadOlder,
        isLoadingOlder: widget.isLoadingOlder,
        olderLoadError: widget.olderLoadError,
        onLoadOlder: widget.onLoadOlder,
        onSelectChannel: widget.onSelectChannel,
      ),
    };
    return Column(
      children: [
        ChatHeader(
          channel: widget.channel,
          channels: widget.channels,
          query: widget.query,
          showCompactPicker: widget.compact,
          allowMemberPanel: widget.allowMemberPanel,
          showMembers: widget.showMembers,
          showPins: widget.showPins,
          inboxSummary: widget.inboxSummary,
          onSelectChannel: widget.onSelectChannel,
          onQueryChanged: widget.onQueryChanged,
          onToggleMembers: widget.onToggleMembers,
          onTogglePins: widget.onTogglePins,
          onOpenInbox: widget.onOpenInbox,
        ),
        Expanded(child: conversation),
        if (widget.channel.kind == ChannelKind.text)
          TypingIndicator(members: widget.typingMembers),
        if (widget.channel.kind == ChannelKind.text)
          MessageComposer(
            channelName: widget.channel.name,
            spaceName: widget.workspace.spaceById(widget.channel.spaceId).name,
            customEmojis: widget.workspace.emojisFor(widget.channel.spaceId),
            isSending: widget.isSending,
            replyTo: _replyTo,
            replyAuthor: _replyTo == null
                ? null
                : widget.workspace.memberOrNull(_replyTo!.authorId),
            onCancelReply: () => setState(() => _replyTo = null),
            onTyping: widget.onTyping,
            onSend: (body, attachments, replyToMessageId) async {
              final sent = await widget.onSend(
                body,
                attachments,
                replyToMessageId,
              );
              if (mounted && sent) setState(() => _replyTo = null);
              return sent;
            },
          ),
      ],
    );
  }
}
