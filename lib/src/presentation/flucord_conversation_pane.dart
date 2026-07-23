part of 'flucord_shell.dart';

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
    required this.allowThreadPanel,
    required this.showMembers,
    required this.showPins,
    required this.showThreads,
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
    required this.onToggleThreads,
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
  final bool allowThreadPanel;
  final bool showMembers;
  final bool showPins;
  final bool showThreads;
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
  final VoidCallback onToggleThreads;
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
          allowThreadPanel: widget.allowThreadPanel,
          showMembers: widget.showMembers,
          showPins: widget.showPins,
          showThreads: widget.showThreads,
          inboxSummary: widget.inboxSummary,
          onSelectChannel: widget.onSelectChannel,
          onQueryChanged: widget.onQueryChanged,
          onToggleMembers: widget.onToggleMembers,
          onTogglePins: widget.onTogglePins,
          onToggleThreads: widget.onToggleThreads,
          onOpenInbox: widget.onOpenInbox,
        ),
        Expanded(child: conversation),
        if (widget.channel.kind == ChannelKind.text &&
            !(widget.channel.isThread &&
                widget.channel.isArchived &&
                widget.channel.isLocked))
          TypingIndicator(members: widget.typingMembers),
        if (widget.channel.kind == ChannelKind.text &&
            widget.channel.isThread &&
            widget.channel.isArchived &&
            widget.channel.isLocked)
          const LockedThreadComposerNotice()
        else if (widget.channel.kind == ChannelKind.text)
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
