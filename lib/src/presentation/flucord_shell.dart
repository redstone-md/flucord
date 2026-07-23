import 'dart:async';

import 'package:flutter/material.dart';

import '../application/chat_controller.dart';
import '../application/connection_controller.dart';
import '../application/workspace_controller.dart';
import '../application/voice_controller.dart';
import '../domain/chat_models.dart';
import 'widgets/channel_sidebar.dart';
import 'widgets/chat_header.dart';
import 'widgets/connection_dialog.dart';
import 'widgets/member_sidebar.dart';
import 'widgets/message_composer.dart';
import 'widgets/message_list.dart';
import 'widgets/pinned_messages_panel.dart';
import 'widgets/server_rail.dart';
import 'widgets/status_views.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/voice_room_view.dart';

class FlucordShell extends StatelessWidget {
  const FlucordShell({
    required this.chatController,
    required this.connectionController,
    required this.workspaceController,
    required this.voiceController,
    super.key,
  });

  final ChatController chatController;
  final ConnectionController connectionController;
  final WorkspaceController workspaceController;
  final VoiceController voiceController;

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
            final channelId = workspaceController.selectedChannelId!;
            final space = workspace.spaceById(spaceId);
            final channels = workspace.channelsFor(spaceId);
            final channel = workspace.channelById(channelId);
            return Scaffold(
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final showChannels = constraints.maxWidth >= 760;
                  final membersFit = constraints.maxWidth >= 1120;
                  final showPins =
                      workspaceController.showPins &&
                      channel.kind == ChannelKind.text;
                  final showMembers =
                      membersFit &&
                      workspaceController.showMembers &&
                      !showPins;
                  return Row(
                    children: [
                      ServerRail(
                        workspace: workspace,
                        selectedSpaceId: spaceId,
                        onSelectSpace: (id) {
                          workspaceController.selectSpace(workspace, id);
                          chatController.openChannel(
                            workspaceController.selectedChannelId!,
                          );
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
                          onSelectChannel: (id) {
                            workspaceController.selectChannel(id);
                            chatController.openChannel(id);
                          },
                          sessionMode: connectionController.mode,
                          connectionStatus: chatController.connectionStatus,
                        ),
                      Expanded(
                        child: _ConversationPane(
                          workspace: workspace,
                          channel: channel,
                          channels: channels,
                          query: workspaceController.query,
                          compact: !showChannels,
                          allowMemberPanel: membersFit,
                          showMembers: showMembers,
                          showPins: showPins,
                          typingMembers: chatController.typingMembersFor(
                            channelId,
                          ),
                          isSending: chatController.isSending,
                          isLoading: chatController.isChannelLoading(channelId),
                          loadError: chatController.channelError(channelId),
                          onRetry: () => chatController.openChannel(
                            channelId,
                            refresh: true,
                          ),
                          onSelectChannel: (id) {
                            workspaceController.selectChannel(id);
                            chatController.openChannel(id);
                          },
                          onQueryChanged: workspaceController.setQuery,
                          onToggleMembers: workspaceController.toggleMembers,
                          onTogglePins: () {
                            workspaceController.togglePins();
                            if (workspaceController.showPins) {
                              unawaited(
                                chatController.loadPinnedMessages(channelId),
                              );
                            }
                          },
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
                          onTogglePin: chatController.togglePin,
                          onTyping: () => chatController.startTyping(channelId),
                          voiceController: voiceController,
                        ),
                      ),
                      if (showPins)
                        PinnedMessagesPanel(
                          workspace: workspace,
                          channelId: channelId,
                          history: chatController.pinnedMessages(channelId),
                          isLoading: chatController.isLoadingPins(channelId),
                          error: chatController.pinError(channelId),
                          onClose: workspaceController.togglePins,
                          onRefresh: () => unawaited(
                            chatController.loadPinnedMessages(
                              channelId,
                              refresh: true,
                            ),
                          ),
                          onUnpin: chatController.togglePin,
                        ),
                      if (showMembers)
                        MemberSidebar(
                          members: workspace.members,
                          spaceId: spaceId,
                        ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  void _openConnections(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => ConnectionDialog(controller: connectionController),
    );
  }
}

class _ConversationPane extends StatefulWidget {
  const _ConversationPane({
    required this.workspace,
    required this.channel,
    required this.channels,
    required this.query,
    required this.compact,
    required this.allowMemberPanel,
    required this.showMembers,
    required this.showPins,
    required this.typingMembers,
    required this.isSending,
    required this.isLoading,
    required this.loadError,
    required this.onRetry,
    required this.onSelectChannel,
    required this.onQueryChanged,
    required this.onToggleMembers,
    required this.onTogglePins,
    required this.onSend,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReaction,
    required this.onAddReaction,
    required this.onTogglePin,
    required this.onTyping,
    required this.voiceController,
  });

  final ChatWorkspace workspace;
  final ConversationChannel channel;
  final List<ConversationChannel> channels;
  final String query;
  final bool compact;
  final bool allowMemberPanel;
  final bool showMembers;
  final bool showPins;
  final List<Member> typingMembers;
  final bool isSending;
  final bool isLoading;
  final Object? loadError;
  final VoidCallback onRetry;
  final ValueChanged<String> onSelectChannel;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleMembers;
  final VoidCallback onTogglePins;
  final SendMessageCallback onSend;
  final Future<bool> Function(ChatMessage, String) onEdit;
  final Future<void> Function(ChatMessage) onDelete;
  final Future<void> Function(ChatMessage, MessageReaction) onToggleReaction;
  final Future<void> Function(ChatMessage, String) onAddReaction;
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
        channelId: widget.channel.id,
        channelName: widget.channel.name,
        controller: widget.voiceController,
      ),
      ChannelKind.text when widget.isLoading => const ChannelLoadingView(),
      ChannelKind.text when widget.loadError != null => ChannelFailureView(
        onRetry: widget.onRetry,
      ),
      ChannelKind.text => MessageList(
        workspace: widget.workspace,
        channel: widget.channel,
        query: widget.query,
        onReply: (message) => setState(() => _replyTo = message),
        onEdit: widget.onEdit,
        onDelete: widget.onDelete,
        onToggleReaction: widget.onToggleReaction,
        onAddReaction: widget.onAddReaction,
        onTogglePin: widget.onTogglePin,
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
          onSelectChannel: widget.onSelectChannel,
          onQueryChanged: widget.onQueryChanged,
          onToggleMembers: widget.onToggleMembers,
          onTogglePins: widget.onTogglePins,
        ),
        Expanded(child: conversation),
        if (widget.channel.kind == ChannelKind.text)
          TypingIndicator(members: widget.typingMembers),
        if (widget.channel.kind == ChannelKind.text)
          MessageComposer(
            channelName: widget.channel.name,
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
