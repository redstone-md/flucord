import 'package:flutter/material.dart';

import '../application/chat_controller.dart';
import '../application/workspace_controller.dart';
import '../domain/chat_models.dart';
import 'widgets/channel_sidebar.dart';
import 'widgets/chat_header.dart';
import 'widgets/member_sidebar.dart';
import 'widgets/message_composer.dart';
import 'widgets/message_list.dart';
import 'widgets/server_rail.dart';
import 'widgets/status_views.dart';

class FlucordShell extends StatelessWidget {
  const FlucordShell({
    required this.chatController,
    required this.workspaceController,
    super.key,
  });

  final ChatController chatController;
  final WorkspaceController workspaceController;

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
    workspaceController.reconcile(workspace);
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
              final showMembers = membersFit && workspaceController.showMembers;
              return Row(
                children: [
                  ServerRail(
                    workspace: workspace,
                    selectedSpaceId: spaceId,
                    onSelectSpace: (id) =>
                        workspaceController.selectSpace(workspace, id),
                    onToggleTheme: workspaceController.toggleTheme,
                    isDark: workspaceController.themeMode == ThemeMode.dark,
                  ),
                  if (showChannels)
                    ChannelSidebar(
                      space: space,
                      channels: channels,
                      selectedChannelId: channelId,
                      onSelectChannel: workspaceController.selectChannel,
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
                      isSending: chatController.isSending,
                      onSelectChannel: workspaceController.selectChannel,
                      onQueryChanged: workspaceController.setQuery,
                      onToggleMembers: workspaceController.toggleMembers,
                      onSend: (body) => chatController.sendMessage(
                        channelId: channel.id,
                        body: body,
                      ),
                    ),
                  ),
                  if (showMembers) MemberSidebar(members: workspace.members),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane({
    required this.workspace,
    required this.channel,
    required this.channels,
    required this.query,
    required this.compact,
    required this.allowMemberPanel,
    required this.showMembers,
    required this.isSending,
    required this.onSelectChannel,
    required this.onQueryChanged,
    required this.onToggleMembers,
    required this.onSend,
  });

  final ChatWorkspace workspace;
  final ConversationChannel channel;
  final List<ConversationChannel> channels;
  final String query;
  final bool compact;
  final bool allowMemberPanel;
  final bool showMembers;
  final bool isSending;
  final ValueChanged<String> onSelectChannel;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleMembers;
  final Future<bool> Function(String body) onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ChatHeader(
          channel: channel,
          channels: channels,
          query: query,
          showCompactPicker: compact,
          allowMemberPanel: allowMemberPanel,
          showMembers: showMembers,
          onSelectChannel: onSelectChannel,
          onQueryChanged: onQueryChanged,
          onToggleMembers: onToggleMembers,
        ),
        Expanded(
          child: channel.kind == ChannelKind.voice
              ? VoiceRoomView(channelName: channel.name)
              : MessageList(
                  workspace: workspace,
                  channel: channel,
                  query: query,
                ),
        ),
        if (channel.kind == ChannelKind.text)
          MessageComposer(
            channelName: channel.name,
            isSending: isSending,
            onSend: onSend,
          ),
      ],
    );
  }
}
