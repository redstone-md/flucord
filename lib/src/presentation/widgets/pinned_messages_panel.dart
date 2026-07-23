import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/external_link_launcher.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';
import 'message_attachment_view.dart';
import 'message_embed_view.dart';
import 'message_content_view.dart';

class PinnedMessagesPanel extends StatelessWidget {
  const PinnedMessagesPanel({
    required this.workspace,
    required this.channelId,
    required this.history,
    required this.isLoading,
    required this.error,
    required this.onClose,
    required this.onRefresh,
    required this.onUnpin,
    required this.linkLauncher,
    required this.onSelectChannel,
    super.key,
  });

  final ChatWorkspace workspace;
  final String channelId;
  final ChannelHistory? history;
  final bool isLoading;
  final Object? error;
  final VoidCallback onClose;
  final VoidCallback onRefresh;
  final Future<void> Function(ChatMessage message) onUnpin;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('pinned-messages-panel'),
      width: 320,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(left: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 58,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Pinned messages',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh pins',
                ),
                IconButton(
                  key: const ValueKey('close-pins-panel'),
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Close pinned messages',
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Divider(height: 1, color: context.surfaces.border),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (isLoading && history == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (error != null && history == null) {
      return _PanelState(
        icon: Icons.error_outline,
        title: 'Pins unavailable',
        action: TextButton(onPressed: onRefresh, child: const Text('Retry')),
      );
    }
    final messages = history?.messages ?? const <ChatMessage>[];
    if (messages.isEmpty) {
      return const _PanelState(
        icon: Icons.push_pin_outlined,
        title: 'No pinned messages',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: context.surfaces.border,
      ),
      itemBuilder: (context, index) => _PinnedMessageRow(
        message: messages[index],
        member: workspace.memberOrNull(messages[index].authorId),
        spaceId: workspace.channelById(channelId).spaceId,
        workspace: workspace,
        linkLauncher: linkLauncher,
        onSelectChannel: onSelectChannel,
        onUnpin: onUnpin,
      ),
    );
  }
}

class _PinnedMessageRow extends StatelessWidget {
  const _PinnedMessageRow({
    required this.message,
    required this.member,
    required this.spaceId,
    required this.workspace,
    required this.linkLauncher,
    required this.onSelectChannel,
    required this.onUnpin,
  });

  final ChatMessage message;
  final Member? member;
  final String spaceId;
  final ChatWorkspace workspace;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;
  final Future<void> Function(ChatMessage message) onUnpin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (member != null)
            MemberAvatar(member: member!, size: 30, spaceId: spaceId),
          if (member == null)
            const SizedBox.square(
              dimension: 30,
              child: Icon(Icons.person_outline, size: 18),
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member?.displayName ?? 'Unknown user',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (message.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 72),
                    child: ClipRect(
                      child: MessageContentView(
                        body: message.body,
                        workspace: workspace,
                        linkLauncher: linkLauncher,
                        onSelectChannel: onSelectChannel,
                        textStyle: const TextStyle(fontSize: 11, height: 1.35),
                      ),
                    ),
                  ),
                ],
                if (message.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: MessageAttachmentView(
                      attachment: message.attachments.first,
                    ),
                  ),
                if (message.embeds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: MessageEmbedView(
                      embed: message.embeds.first,
                      workspace: workspace,
                      linkLauncher: linkLauncher,
                      onSelectChannel: onSelectChannel,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => onUnpin(message),
            icon: const Icon(Icons.push_pin_outlined, size: 16),
            tooltip: 'Unpin message',
          ),
        ],
      ),
    );
  }
}

class _PanelState extends StatelessWidget {
  const _PanelState({required this.icon, required this.title, this.action});

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 26, color: context.surfaces.muted),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontSize: 12)),
        ?action,
      ],
    ),
  );
}
