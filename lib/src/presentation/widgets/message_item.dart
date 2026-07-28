import 'dart:async';
import '../../domain/application_command.dart';
import '../../application/slash_command_controller.dart';
import '../../application/message_component_controller.dart';
import 'application_command_menu.dart';
import 'component_directory_picker.dart';
import 'message_component_row.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/channel_capabilities.dart';
import '../../domain/chat_models.dart';
import '../../domain/attachment_download.dart';
import '../../domain/external_link_launcher.dart';
import '../../theme/flucord_theme.dart';
import 'create_thread_dialog.dart';
import 'forwarded_message_view.dart';
import 'member_avatar.dart';
import 'message_action_bar.dart';
import 'message_attachment_gallery.dart';
import 'message_content_view.dart';
import 'message_embed_view.dart';
import 'message_forward_dialog.dart';
import 'message_poll_view.dart';
import 'message_reaction_strip.dart';
import 'message_sticker_view.dart';
import 'message_timestamp.dart';
import 'reaction_details_dialog.dart';
import 'user_settings_scope.dart';

class MessageItem extends StatefulWidget {
  const MessageItem({
    required this.message,
    required this.member,
    required this.workspace,
    required this.grouped,
    required this.isCurrentUser,
    this.capabilities = ChannelCapabilities.unrestricted,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleReaction,
    required this.onLoadReactionUsers,
    required this.onAddReaction,
    required this.onCreateThread,
    required this.onTogglePin,
    required this.onEndPoll,
    required this.onForward,
    required this.onToggleSuppressEmbeds,
    required this.linkLauncher,
    required this.onSelectChannel,
    this.componentController,
    this.applicationCommands,
    this.attachmentDownloadService,
    super.key,
  });

  final ChatMessage message;

  /// Presses the buttons and selects an application hung off this message.
  /// Null on a transport that cannot send interactions.
  final MessageComponentController? componentController;

  /// The Apps menu's controller, or null where context commands cannot run.
  final SlashCommandController? applicationCommands;
  final Member member;
  final ChatWorkspace workspace;
  final bool grouped;
  final bool isCurrentUser;

  /// Which actions this channel's permissions allow. Unrestricted by default
  /// so a host with no permission data keeps the toolbar it had.
  final ChannelCapabilities capabilities;
  final ValueChanged<ChatMessage> onReply;
  final Future<bool> Function(ChatMessage, String) onEdit;
  final Future<void> Function(ChatMessage) onDelete;
  final Future<void> Function(ChatMessage, MessageReaction) onToggleReaction;
  final ReactionUsersLoader onLoadReactionUsers;
  final Future<void> Function(ChatMessage, String) onAddReaction;
  final Future<bool> Function(ChatMessage, String, int) onCreateThread;
  final Future<void> Function(ChatMessage) onTogglePin;
  final Future<bool> Function(ChatMessage) onEndPoll;
  final ForwardMessageCallback onForward;
  final Future<bool> Function(ChatMessage) onToggleSuppressEmbeds;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;
  final AttachmentDownloadService? attachmentDownloadService;

  @override
  State<MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<MessageItem> {
  bool _hovered = false;
  bool _editing = false;
  bool _reactionPickerOpen = false;
  late final TextEditingController _editController = TextEditingController(
    text: widget.message.body,
  );
  final FocusNode _editFocus = FocusNode();

  @override
  void didUpdateWidget(covariant MessageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.message.body != widget.message.body) {
      _editController.text = widget.message.body;
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  Future<void> _saveEdit() async {
    final content = _editController.text.trim();
    if (content.isEmpty) return;
    final saved = await widget.onEdit(widget.message, content);
    if (mounted && saved) setState(() => _editing = false);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.onDelete(widget.message);
  }

  @override
  Widget build(BuildContext context) {
    final time = MessageTimestamp.of(context, widget.message.sentAt);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _hovered
                  ? context.surfaces.raised.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
            padding: EdgeInsets.fromLTRB(20, widget.grouped ? 3 : 9, 20, 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 38,
                  child: widget.grouped
                      ? Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            time,
                            style: TextStyle(
                              color: context.surfaces.muted,
                              fontSize: 9,
                            ),
                          ),
                        )
                      : MemberAvatar(
                          member: widget.member,
                          size: 34,
                          spaceId: widget.workspace
                              .channelById(widget.message.channelId)
                              .spaceId,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _content(context, time)),
              ],
            ),
          ),
          if ((_hovered || _reactionPickerOpen) && !_editing)
            Positioned(right: 18, top: -12, child: _actionBar(context)),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, String time) {
    final message = widget.message;
    final display = UserSettingsScope.displayOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.grouped) _authorLine(context, time),
        if (message.reply case final reply?) _replyLine(context, reply),
        if (_editing)
          _editField(context)
        else if (message.body.isNotEmpty)
          MessageContentView(
            body: message.body,
            workspace: widget.workspace,
            linkLauncher: widget.linkLauncher,
            onSelectChannel: widget.onSelectChannel,
          ),
        for (var index = 0; index < message.snapshots.length; index++)
          Padding(
            padding: EdgeInsets.only(
              top: message.body.isEmpty && index == 0 ? 0 : 7,
            ),
            child: ForwardedMessageView(
              key: ValueKey('message-${message.id}-snapshot-$index'),
              snapshot: message.snapshots[index],
              reference: message.reference ?? const MessageReference(),
              workspace: widget.workspace,
              linkLauncher: widget.linkLauncher,
              onSelectChannel: widget.onSelectChannel,
            ),
          ),
        if (message.isEdited && !_editing)
          Text(
            '(edited)',
            style: TextStyle(color: context.surfaces.muted, fontSize: 9),
          ),
        if (message.attachments.isNotEmpty)
          MessageAttachmentGallery(
            attachments: message.attachments,
            rendersMedia: display.rendersAttachmentMedia,
            downloadService: widget.attachmentDownloadService,
          ),
        if (!message.suppressesEmbeds && display.rendersEmbeds)
          for (var index = 0; index < message.embeds.length; index++)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: MessageEmbedView(
                key: ValueKey('message-${message.id}-embed-$index'),
                embed: message.embeds[index],
                workspace: widget.workspace,
                linkLauncher: widget.linkLauncher,
                onSelectChannel: widget.onSelectChannel,
              ),
            ),
        if (message.stickers.isNotEmpty)
          MessageStickerStrip(stickers: message.stickers),
        // The buttons an application put on this message. Drawn under the
        // content and above the poll, which is where Discord puts them.
        if (widget.componentController case final controller?
            when message.componentRows.isNotEmpty)
          ListenableBuilder(
            listenable: controller,
            builder: (_, _) => MessageComponentRows(
              controller: controller,
              rows: message.componentRows,
              messageId: message.id,
              applicationId: message.authorId,
              messageFlags: message.flags,
              onOpenLink: (url) =>
                  unawaited(widget.linkLauncher.open(Uri.parse(url))),
              directoryEntries: (component) => ComponentDirectory.entriesFor(
                component,
                workspace: widget.workspace,
                spaceId:
                    widget.workspace
                        .channelOrNull(message.channelId)
                        ?.spaceId ??
                    '',
              ),
            ),
          ),
        if (message.poll case final poll?)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: MessagePollView(
              poll: poll,
              canEnd: widget.isCurrentUser,
              onEnd: () => unawaited(widget.onEndPoll(message)),
            ),
          ),
        if (message.reactions.isNotEmpty && display.rendersReactions) ...[
          const SizedBox(height: 6),
          MessageReactionStrip(
            message: message,
            workspace: widget.workspace,
            onToggle: (reaction) =>
                unawaited(widget.onToggleReaction(message, reaction)),
            onShowDetails: _showReactionDetails,
          ),
        ],
      ],
    );
  }

  Widget _authorLine(BuildContext context, String time) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        Text(
          widget.member.displayName,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Text(
          time,
          style: TextStyle(color: context.surfaces.muted, fontSize: 10),
        ),
      ],
    ),
  );

  Widget _replyLine(BuildContext context, MessageReply reply) {
    final author = widget.workspace.memberOrNull(reply.authorId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.subdirectory_arrow_right,
            size: 13,
            color: context.surfaces.muted,
          ),
          const SizedBox(width: 5),
          Text(
            author?.displayName ?? 'Unknown user',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              reply.body.isEmpty ? 'Message unavailable' : reply.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.surfaces.muted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editField(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _saveEdit,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            setState(() => _editing = false);
          },
        },
        child: TextField(
          key: ValueKey('edit-${widget.message.id}'),
          controller: _editController,
          focusNode: _editFocus,
          autofocus: true,
          maxLines: 4,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Escape to cancel · Enter to save',
        style: TextStyle(color: context.surfaces.muted, fontSize: 9),
      ),
    ],
  );

  Widget _actionBar(BuildContext context) => MessageActionBar(
    apps: widget.applicationCommands == null
        ? null
        : ApplicationCommandMenuButton(
            controller: widget.applicationCommands!,
            type: ApplicationCommandType.message,
            targetId: widget.message.id,
          ),
    message: widget.message,
    workspace: widget.workspace,
    capabilities: widget.capabilities,
    isCurrentUser: widget.isCurrentUser,
    onReply: () => widget.onReply(widget.message),
    onAddReaction: (emoji) =>
        unawaited(widget.onAddReaction(widget.message, emoji)),
    onReactionPickerToggled: (isOpen) {
      if (mounted) setState(() => _reactionPickerOpen = isOpen);
    },
    onShowReactionDetails: _showReactionDetails,
    onCreateThread: _showCreateThreadDialog,
    onForward: _showForwardDialog,
    onToggleSuppressEmbeds: () =>
        unawaited(widget.onToggleSuppressEmbeds(widget.message)),
    onEdit: () {
      setState(() => _editing = true);
      _editFocus.requestFocus();
    },
    onTogglePin: () => widget.onTogglePin(widget.message),
    onDelete: _confirmDelete,
  );

  void _showReactionDetails(MessageReaction reaction) {
    unawaited(
      ReactionDetailsDialog.show(
        context,
        message: widget.message,
        workspace: widget.workspace,
        initialReaction: reaction,
        onLoad: widget.onLoadReactionUsers,
      ),
    );
  }

  void _showCreateThreadDialog() {
    unawaited(
      CreateThreadDialog.show(
        context,
        onCreate: (name, duration) =>
            widget.onCreateThread(widget.message, name, duration),
      ),
    );
  }

  void _showForwardDialog() {
    unawaited(
      MessageForwardDialog.show(
        context,
        message: widget.message,
        workspace: widget.workspace,
        onForward: widget.onForward,
      ),
    );
  }
}
