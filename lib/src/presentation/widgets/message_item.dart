import '../../application/expression_favorites_controller.dart';
import '../../domain/automod_rule.dart';
import 'dart:async';

import 'emoji_picker.dart';
import 'message_context_menu.dart';
import '../../domain/application_command.dart';
import '../../application/slash_command_controller.dart';
import '../../application/message_component_controller.dart';
import 'application_command_menu.dart';
import 'chat_scope.dart';
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
import 'destructive_confirmation.dart';
import 'forwarded_message_view.dart';
import 'member_avatar.dart';
import 'message_action_bar.dart';
import 'message_attachment_gallery.dart';
import 'message_content_view.dart';
import 'message_embed_view.dart';
import 'message_forward_dialog.dart';
import 'message_poll_view.dart';
import 'message_preview_text.dart';
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
    this.onMarkUnread,
    required this.onCreateThread,
    required this.onTogglePin,
    this.onResolveAlert,
    this.onReport,
    required this.onEndPoll,
    required this.onForward,
    required this.onToggleSuppressEmbeds,
    required this.linkLauncher,
    required this.onSelectChannel,
    this.onOpenMemberProfile,
    this.onOpenMessage,
    this.componentController,
    this.applicationCommands,
    this.expressionFavorites,
    this.attachmentDownloadService,
    super.key,
  });

  /// The starred expressions, when the transport holds any.
  final ExpressionFavoritesController? expressionFavorites;
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

  /// Makes this message and everything after it unread again. Null on a
  /// transport with no read state.
  final Future<void> Function(ChatMessage)? onMarkUnread;
  final Future<bool> Function(ChatMessage, String, int) onCreateThread;
  final Future<void> Function(ChatMessage) onTogglePin;

  /// Acts on an AutoMod alert, or null where the transport cannot.
  final Future<void> Function(ChatMessage, AutoModAlertAction)? onResolveAlert;

  /// Opens the report flow for a message, or null where there is none.
  final void Function(ChatMessage)? onReport;
  final Future<bool> Function(ChatMessage) onEndPoll;
  final ForwardMessageCallback onForward;
  final Future<bool> Function(ChatMessage) onToggleSuppressEmbeds;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;

  /// Opens the profile of the user with this id. Null where no profile can
  /// show, which leaves the author's name and avatar as plain content.
  final ValueChanged<String>? onOpenMemberProfile;

  /// Jumps to another message of this channel, by id.
  final ValueChanged<String>? onOpenMessage;
  final AttachmentDownloadService? attachmentDownloadService;

  @override
  State<MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<MessageItem> {
  bool _hovered = false;
  bool _editing = false;
  bool _reactionPickerOpen = false;

  /// The text selected in this row now. Opening the menu takes focus, and that
  /// clears the selection, so the menu keeps its own copy.
  String _selectedText = '';
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

  /// The workspace for an action, which can reach past what this row draws.
  ChatWorkspace get _workspaceNow =>
      ChatScope.workspaceNow(context, widget.workspace);

  Future<void> _saveEdit() async {
    final content = _editController.text.trim();
    if (content.isEmpty) return;
    final saved = await widget.onEdit(widget.message, content);
    if (mounted && saved) setState(() => _editing = false);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete message?',
      message: 'This message will be permanently deleted.',
      confirmLabel: 'Delete',
    );
    if (confirmed) await widget.onDelete(widget.message);
  }

  @override
  Widget build(BuildContext context) {
    // The account's density answer, read in the row rather than threaded
    // through constructors: a change from another device tightens the list
    // without anybody rebuilding it by hand.
    final compact = UserSettingsScope.appearanceOf(context).packsDensely;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // The right button reaches the same actions the hover bar carries.
        // Without it half of them were only discoverable by hovering the
        // exact right pixels, and copying an id or a link had nowhere to live.
        onSecondaryTapDown: (details) =>
            unawaited(_openContextMenu(context, details.globalPosition)),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: _hovered
                    ? context.surfaces.raised.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
              // The bar must fit inside the row. A part of it outside the row
              // gets no clicks, and the pointer there hovers the next row.
              constraints: const BoxConstraints(
                minHeight: MessageActionBar.height,
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                widget.grouped ? (compact ? 2 : 3) : (compact ? 6 : 9),
                20,
                compact ? 4 : 5,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 38,
                    child: widget.grouped
                        ? Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: MessageTimeLabel(
                              widget.message.sentAt,
                              style: TextStyle(
                                color: context.surfaces.muted,
                                fontSize: 9,
                              ),
                            ),
                          )
                        : _opensAuthorProfile(
                            key: const ValueKey('message-author-avatar'),
                            child: MemberAvatar(
                              member: widget.member,
                              size: 34,
                              spaceId: widget.workspace
                                  .channelById(widget.message.channelId)
                                  .spaceId,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MessageMenuScope(
                      onOpen: (position) =>
                          unawaited(_openContextMenu(context, position)),
                      onSelectionChanged: (content) =>
                          _selectedText = content?.plainText ?? '',
                      child: _content(context),
                    ),
                  ),
                ],
              ),
            ),
            if ((_hovered || _reactionPickerOpen) && !_editing)
              Positioned(right: 18, top: 0, child: _actionBar(context)),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final message = widget.message;
    final display = UserSettingsScope.displayOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.grouped) _authorLine(context),
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
                workspace: _workspaceNow,
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

  Widget _authorLine(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        Flexible(
          child: _opensAuthorProfile(
            key: const ValueKey('message-author-name'),
            child: Text(
              widget.member.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _nameColor(widget.member),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        MessageTimeLabel(
          widget.message.sentAt,
          style: TextStyle(color: context.surfaces.muted, fontSize: 10),
        ),
        // The flags a reader cannot guess from the text: why nothing
        // notified them, and why the machine just spoke.
        if (widget.message.suppressesNotifications) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: 'Silent message',
            child: Icon(
              Icons.notifications_off_outlined,
              key: const ValueKey('silent-message-marker'),
              size: 11,
              color: context.surfaces.muted,
            ),
          ),
        ],
        if (widget.message.isTextToSpeech) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: 'Text-to-speech message',
            child: Icon(
              Icons.record_voice_over_outlined,
              key: const ValueKey('text-to-speech-message-marker'),
              size: 11,
              color: context.surfaces.muted,
            ),
          ),
        ],
      ],
    ),
  );

  /// The colour of [member]'s role here, or null for the normal text colour.
  Color? _nameColor(Member member) {
    final spaceId = widget.workspace
        .channelOrNull(widget.message.channelId)
        ?.spaceId;
    final value = spaceId == null
        ? null
        : widget.workspace.nameColorOf(member, spaceId);
    return value == null ? null : Color(value);
  }

  /// Makes [child] a target for the pointer, or leaves it as it is when there
  /// is nothing to do. The label replaces what [child] would announce.
  Widget _clickable({
    required Key key,
    required String label,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    if (onTap == null) return child;
    return Semantics(
      button: true,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }

  Widget _opensAuthorProfile({required Key key, required Widget child}) {
    final open = widget.onOpenMemberProfile;
    return _clickable(
      key: key,
      label: '${widget.member.displayName} profile',
      onTap: open == null ? null : () => open(widget.message.authorId),
      child: child,
    );
  }

  Widget _replyLine(BuildContext context, MessageReply reply) {
    final author = widget.workspace.memberOrNull(reply.authorId);
    final open = widget.onOpenMessage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _clickable(
        key: const ValueKey('message-reply-preview'),
        label: 'Go to the replied message',
        onTap: open == null ? null : () => open(reply.messageId),
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
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: author == null ? null : _nameColor(author),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                reply.body.isEmpty
                    ? 'Message unavailable'
                    : messagePreviewText(context, reply.body, widget.workspace),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.surfaces.muted, fontSize: 10),
              ),
            ),
          ],
        ),
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

  Future<void> _openContextMenu(BuildContext context, Offset position) async {
    final selectedText = _selectedText;
    final action = await showMessageContextMenu(
      context: context,
      position: position,
      message: widget.message,
      capabilities: widget.capabilities,
      isCurrentUser: widget.isCurrentUser,
      canMarkUnread: widget.onMarkUnread != null,
      selectedText: selectedText,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case MessageMenuAction.addReaction:
        await _pickReactionAt(position);
      case MessageMenuAction.markUnread:
        await widget.onMarkUnread?.call(widget.message);
      case MessageMenuAction.reply:
        widget.onReply(widget.message);
      case MessageMenuAction.edit:
        setState(() => _editing = true);
        _editFocus.requestFocus();
      case MessageMenuAction.pin:
        await widget.onTogglePin(widget.message);
      case MessageMenuAction.forward:
        _showForwardDialog();
      case MessageMenuAction.createThread:
        _showCreateThreadDialog();
      case MessageMenuAction.copySelection:
        await copyToClipboard(selectedText);
      case MessageMenuAction.copyText:
        await copyToClipboard(widget.message.body);
      case MessageMenuAction.copyLink:
        await copyToClipboard(
          messageLink(
            spaceId:
                widget.workspace
                    .channelOrNull(widget.message.channelId)
                    ?.spaceId ??
                '',
            channelId: widget.message.channelId,
            messageId: widget.message.id,
          ),
        );
      case MessageMenuAction.copyId:
        await copyToClipboard(widget.message.id);
      case MessageMenuAction.delete:
        await _confirmDelete();
    }
  }

  Future<void> _pickReactionAt(Offset position) async {
    final workspace = _workspaceNow;
    final spaceId = workspace.channelById(widget.message.channelId).spaceId;
    final emoji = await showEmojiPickerAt(
      context: context,
      position: position,
      spaceName: workspace.spaceById(spaceId).name,
      emojiSections: emojiSectionsFromWorkspace(workspace, spaceId),
      purpose: EmojiPickerPurpose.reaction,
      favorites: widget.expressionFavorites,
    );
    if (emoji != null && mounted) {
      await widget.onAddReaction(widget.message, emoji);
    }
  }

  Widget _actionBar(BuildContext context) => MessageActionBar(
    expressionFavorites: widget.expressionFavorites,
    apps: widget.applicationCommands == null
        ? null
        : ApplicationCommandMenuButton(
            controller: widget.applicationCommands!,
            type: ApplicationCommandType.message,
            targetId: widget.message.id,
          ),
    message: widget.message,
    workspace: _workspaceNow,
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
    onResolveAlert: widget.onResolveAlert == null
        ? null
        : (action) => unawaited(widget.onResolveAlert!(widget.message, action)),
    onReport: widget.onReport == null
        ? null
        : () => widget.onReport!(widget.message),
    onDelete: _confirmDelete,
  );

  void _showReactionDetails(MessageReaction reaction) {
    unawaited(
      ReactionDetailsDialog.show(
        context,
        message: widget.message,
        workspace: _workspaceNow,
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
        workspace: _workspaceNow,
        onForward: widget.onForward,
      ),
    );
  }
}
