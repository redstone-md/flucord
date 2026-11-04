import '../../application/expression_favorites_controller.dart';
import '../../domain/automod_rule.dart';
import 'dart:async';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_type.dart';
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
import 'message_invite_cards.dart';
import 'message_forward_dialog.dart';
import 'message_poll_view.dart';
import 'message_preview_text.dart';
import 'message_reaction_strip.dart';
import 'message_reply_line.dart';
import 'message_row_metrics.dart';
import 'message_sticker_view.dart';
import 'profile_card_route.dart';
import 'message_timestamp.dart';
import 'name_tags.dart';
import 'reaction_details_dialog.dart';
import 'streamer_mode_scope.dart';
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
    this.isEditing = false,
    this.onEditingChanged,
    this.onEditClosed,
    super.key,
  });

  /// The starred expressions, when the transport holds any.
  final ExpressionFavoritesController? expressionFavorites;
  final ChatMessage message;

  /// Whether this row shows its edit field. The list decides, because the list
  /// is what the keyboard reaches and only one row edits at a time.
  final bool isEditing;

  /// Asks to open or close the edit field. Null where no list holds the row.
  final ValueChanged<bool>? onEditingChanged;

  /// An edit that was not opened from this row closed, saved or not.
  final VoidCallback? onEditClosed;

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

  /// Opens the author's profile beside their name or avatar. Null where no
  /// profile can show, which leaves both as plain content.
  final OpenProfileCard? onOpenMemberProfile;

  /// Jumps to another message of this channel, by id.
  final ValueChanged<String>? onOpenMessage;
  final AttachmentDownloadService? attachmentDownloadService;

  @override
  State<MessageItem> createState() => _MessageItemState();
}

class _MessageItemState extends State<MessageItem> {
  bool _hovered = false;
  bool _barHovered = false;
  bool _reactionPickerOpen = false;

  /// The toolbar floats in the overlay. It reaches above the row, and a part
  /// of a row outside its own bounds would get no clicks.
  final OverlayPortalController _barPortal = OverlayPortalController(
    debugLabel: 'message action bar',
  );

  /// The text selected in this row now. Opening the menu takes focus, and that
  /// clears the selection, so the menu keeps its own copy.
  String _selectedText = '';
  late final TextEditingController _editController = TextEditingController(
    text: widget.message.body,
  );
  final FocusNode _editFocus = FocusNode();

  /// Whether the focus was in this row when its edit field opened.
  bool _editOpenedFromRow = false;

  /// The row as one stop for the keyboard and for a screen reader.
  final FocusNode _rowFocus = FocusNode(debugLabel: 'message row');

  /// Holds the action bar's buttons, to tell them from the text of the row. A
  /// click on the text takes focus too, and must not pin the bar in place.
  final FocusNode _barFocus = FocusNode(
    debugLabel: 'message action bar',
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    _rowFocus.addListener(_redrawForFocus);
    _barFocus.addListener(_redrawForFocus);
    if (widget.isEditing) _focusEditField();
  }

  void _redrawForFocus() => _updateBar(() {});

  /// Applies [change], then shows or hides the toolbar to match. Never called
  /// during a build, which the overlay does not allow.
  void _updateBar(VoidCallback change) {
    setState(change);
    final wanted =
        _hovered ||
        _barHovered ||
        _reactionPickerOpen ||
        _rowFocus.hasPrimaryFocus ||
        _barFocus.hasFocus;
    if (wanted == _barPortal.isShowing) return;
    wanted ? _barPortal.show() : _barPortal.hide();
  }

  @override
  void didUpdateWidget(covariant MessageItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEditing && !oldWidget.isEditing) {
      _editOpenedFromRow = _rowFocus.hasFocus;
      // Words given up last time do not come back.
      _editController.text = widget.message.body;
      _focusEditField();
    } else if (!widget.isEditing &&
        oldWidget.message.body != widget.message.body) {
      _editController.text = widget.message.body;
    }
  }

  /// Closes the edit field, and gives the focus back to where it was when the
  /// field opened: the row for a keyboard that came through the row, and
  /// otherwise the place where the next message is written.
  void _closeEdit() {
    widget.onEditingChanged?.call(false);
    if (_editOpenedFromRow) {
      _rowFocus.requestFocus();
    } else {
      widget.onEditClosed?.call();
    }
  }

  /// The field joins the tree in this build, so it can take the focus after.
  void _focusEditField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocus.dispose();
    _rowFocus.dispose();
    _barFocus.dispose();
    super.dispose();
  }

  /// The workspace for an action, which can reach past what this row draws.
  ChatWorkspace get _workspaceNow =>
      ChatScope.workspaceNow(context, widget.workspace);

  Future<void> _saveEdit() async {
    final content = _editController.text.trim();
    if (content.isEmpty) return;
    // Read first: the row may scroll away while the request runs.
    final onEditingChanged = widget.onEditingChanged;
    final saved = await widget.onEdit(widget.message, content);
    if (!saved) return;
    if (mounted) {
      _closeEdit();
    } else {
      onEditingChanged?.call(false);
    }
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
    final groupGap = widget.grouped
        ? 0.0
        : compact
        ? MessageRowMetrics.compactGroupGap
        : MessageRowMetrics.groupGap;
    return Semantics(
      container: true,
      // The parts of the row stay their own nodes, so links, attachments and
      // buttons inside it can still be reached one by one.
      explicitChildNodes: true,
      label: _announcement(context),
      focusable: true,
      focused: _rowFocus.hasPrimaryFocus,
      onFocus: _rowFocus.requestFocus,
      child: Focus(
        focusNode: _rowFocus,
        includeSemantics: false,
        child: Padding(
          padding: EdgeInsets.only(top: groupGap),
          child: OverlayPortal.overlayChildLayoutBuilder(
            controller: _barPortal,
            overlayChildBuilder: _floatingBar,
            child: MouseRegion(
              onEnter: (_) => _updateBar(() => _hovered = true),
              onExit: (_) => _updateBar(() => _hovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                // The right button reaches the same actions the hover bar
                // carries. Without it half of them were only discoverable by
                // hovering the exact right pixels, and copying an id or a
                // link had nowhere to live.
                onSecondaryTapDown: (details) => unawaited(
                  _openContextMenu(context, details.globalPosition),
                ),
                child: Stack(
                  children: [
                    _surface(context),
                    if (_rowFocus.hasPrimaryFocus)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            key: const ValueKey('message-focus-ring'),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: context.surfaces.focusRing,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The highlight that wraps the message. Hover and mention fill it, and
  /// its padding is the same above and below, so the fill sits evenly.
  Widget _surface(BuildContext context) {
    final surfaces = context.surfaces;
    final mentioned = widget.message.mentionsCurrentMember;
    final block = mentioned
        ? MessageRowMetrics.mentionBlock
        : widget.grouped
        ? MessageRowMetrics.followUpBlock
        : MessageRowMetrics.block;
    return Container(
      key: ValueKey('message-surface-${widget.message.id}'),
      // Both always set, even when they draw nothing: a box that came and
      // went with the hover would rebuild the text and drop its selection.
      color: mentioned
          ? surfaces.brand.withValues(alpha: MessageRowMetrics.mentionAlpha)
          : _hovered
          ? surfaces.text.withValues(alpha: MessageRowMetrics.hoverAlpha)
          : Colors.transparent,
      foregroundDecoration: BoxDecoration(
        border: mentioned
            ? BorderDirectional(
                start: BorderSide(
                  color: surfaces.brand,
                  width: MessageRowMetrics.mentionBarWidth,
                ),
              )
            : null,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: MessageRowMetrics.inline,
        vertical: block,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.message.reply case final reply?) ...[
            _replyLine(context, reply),
            const SizedBox(height: MessageRowMetrics.replyGap),
          ],
          _authorAndContent(context),
        ],
      ),
    );
  }

  /// The avatar lane and, beside it, the name row and everything below.
  Widget _authorAndContent(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: MessageRowMetrics.avatarSize,
        child: widget.grouped
            ? _followUpTime(context)
            : _opensAuthorProfile(
                key: const ValueKey('message-author-avatar'),
                child: MemberAvatar(
                  member: widget.member,
                  size: MessageRowMetrics.avatarSize,
                  spaceId: widget.workspace
                      .channelById(widget.message.channelId)
                      .spaceId,
                ),
              ),
      ),
      const SizedBox(width: MessageRowMetrics.avatarGap),
      Expanded(
        child: MessageMenuScope(
          onOpen: (position) => unawaited(_openContextMenu(context, position)),
          onSelectionChanged: (content) =>
              _selectedText = content?.plainText ?? '',
          child: _content(context),
        ),
      ),
    ],
  );

  /// A follow-up's clock, in the avatar's lane. It sits on the first line of
  /// text, and may spill into the gaps beside the lane, since `12:59 PM` is
  /// wider than the lane.
  Widget _followUpTime(BuildContext context) {
    return SizedBox(
      height: FlucordTextRole.body.lineHeight,
      child: OverflowBox(
        maxWidth:
            MessageRowMetrics.avatarSize + 2 * MessageRowMetrics.avatarGap,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: MessageTimeLabel(
            widget.message.sentAt,
            style: _captionStyle(context),
          ),
        ),
      ),
    );
  }

  TextStyle _captionStyle(BuildContext context) => FlucordTextRole.caption.style
      .copyWith(color: context.surfaces.captionText);

  /// The toolbar, over the right end of the highlight's top edge. It never
  /// rises above the list the row scrolls in, so the topmost message keeps it
  /// off the chat header.
  Widget _floatingBar(BuildContext context, OverlayChildLayoutInfo layout) {
    // A transform that flattens the row means it is not on screen.
    if (widget.isEditing || layout.childPaintTransform.determinant() == 0) {
      return const SizedBox.shrink();
    }
    final surface = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    final top = surface.top - MessageRowMetrics.barRise;
    return Positioned(
      top: switch (_listTop()) {
        final listTop? when listTop > top => listTop,
        _ => top,
      },
      right:
          layout.overlaySize.width - surface.right + MessageRowMetrics.inline,
      child: MouseRegion(
        onEnter: (_) => _updateBar(() => _barHovered = true),
        onExit: (_) => _updateBar(() => _barHovered = false),
        child: Focus(
          focusNode: _barFocus,
          includeSemantics: false,
          child: _actionBar(context),
        ),
      ),
    );
  }

  /// The top edge of the list this row scrolls in, in the overlay's space,
  /// or null for a row in no list.
  double? _listTop() {
    final list = Scrollable.maybeOf(context)?.context.findRenderObject();
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (list is! RenderBox || overlay == null) return null;
    return list.localToGlobal(Offset.zero, ancestor: overlay).dy;
  }

  /// What a screen reader says when the row takes focus: author, time, text.
  String _announcement(BuildContext context) {
    final body = StreamerModeScope.redact(context, widget.message.body);
    return [
      widget.member.displayName,
      MessageTimestamp.longOf(context, widget.message.sentAt),
      if (body.isNotEmpty) messagePreviewText(context, body, widget.workspace),
    ].join(', ');
  }

  Widget _content(BuildContext context) {
    final message = widget.message;
    final display = UserSettingsScope.displayOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.grouped) _authorLine(context),
        if (widget.isEditing)
          _editField(context)
        else if (message.body.isNotEmpty)
          MessageContentView(
            body: message.body,
            textStyle: FlucordTextRole.body.style.copyWith(
              color: context.surfaces.bodyText,
            ),
            workspace: widget.workspace,
            linkLauncher: widget.linkLauncher,
            onSelectChannel: widget.onSelectChannel,
          ),
        if (!widget.isEditing && message.body.isNotEmpty)
          MessageInviteCards(
            body: message.body,
            sentByMe: widget.isCurrentUser,
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
        if (message.isEdited && !widget.isEditing)
          Text('(edited)', style: _captionStyle(context)),
        if (message.attachments.isNotEmpty)
          MessageAttachmentGallery(
            attachments: message.attachments,
            rendersMedia: display.rendersAttachmentMedia,
            downloadService: widget.attachmentDownloadService,
          ),
        if (!message.suppressesEmbeds && display.rendersEmbeds)
          for (var index = 0; index < message.embeds.length; index++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
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

  /// The name and the time, on a row whose top meets the avatar's top.
  Widget _authorLine(BuildContext context) {
    final muted = context.surfaces.captionText;
    return SizedBox(
      height: MessageRowMetrics.nameRowHeight,
      child: Row(
        children: [
          Flexible(
            child: _opensAuthorProfile(
              key: const ValueKey('message-author-name'),
              child: Text(
                widget.member.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.heading.style.copyWith(
                  height:
                      MessageRowMetrics.nameRowHeight /
                      FlucordTextRole.heading.size,
                  color: _nameColor(widget.member),
                ),
              ),
            ),
          ),
          NameTags(member: widget.member),
          const SizedBox(width: 8),
          MessageTimeLabel(
            widget.message.sentAt,
            style: _captionStyle(context),
          ),
          // The flags a reader cannot guess from the text: why nothing
          // notified them, and why the machine just spoke.
          if (widget.message.suppressesNotifications) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Silent message',
              child: FlucordIcon(
                FlucordIcons.silent,
                key: const ValueKey('silent-message-marker'),
                size: FlucordType.caption,
                color: muted,
              ),
            ),
          ],
          if (widget.message.isTextToSpeech) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Text-to-speech message',
              child: FlucordIcon(
                FlucordIcons.spoken,
                key: const ValueKey('text-to-speech-message-marker'),
                size: FlucordType.caption,
                color: muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

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
    return Builder(
      builder: (context) => _clickable(
        key: key,
        label: '${widget.member.displayName} profile',
        onTap: open == null
            ? null
            : () => open(widget.message.authorId, profileCardAnchorOf(context)),
        child: child,
      ),
    );
  }

  /// The reply line: a spine in the avatar lane, curving into what the
  /// message answers, which sits in the text column.
  Widget _replyLine(BuildContext context, MessageReply reply) {
    final open = widget.onOpenMessage;
    final author = widget.workspace.memberOrNull(reply.authorId);
    return Row(
      children: [
        const MessageReplySpine(
          laneWidth: MessageRowMetrics.avatarSize + MessageRowMetrics.avatarGap,
          avatarSize: MessageRowMetrics.avatarSize,
        ),
        Expanded(
          child: _clickable(
            key: const ValueKey('message-reply-preview'),
            label: 'Go to the replied message',
            onTap: open == null ? null : () => open(reply.messageId),
            child: MessageReplyPreview(
              reply: reply,
              author: author,
              workspace: widget.workspace,
              nameColor: author == null ? null : _nameColor(author),
              spaceId: widget.workspace
                  .channelOrNull(widget.message.channelId)
                  ?.spaceId,
            ),
          ),
        ),
      ],
    );
  }

  Widget _editField(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _saveEdit,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): _saveEdit,
          const SingleActivator(LogicalKeyboardKey.escape): _closeEdit,
        },
        child: TextField(
          key: ValueKey('edit-${widget.message.id}'),
          controller: _editController,
          focusNode: _editFocus,
          maxLines: 4,
        ),
      ),
      const SizedBox(height: 4),
      Text('Escape to cancel · Enter to save', style: _captionStyle(context)),
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
        widget.onEditingChanged?.call(true);
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
      if (mounted) _updateBar(() => _reactionPickerOpen = isOpen);
    },
    onShowReactionDetails: _showReactionDetails,
    onCreateThread: _showCreateThreadDialog,
    onForward: _showForwardDialog,
    onToggleSuppressEmbeds: () =>
        unawaited(widget.onToggleSuppressEmbeds(widget.message)),
    onEdit: () => widget.onEditingChanged?.call(true),
    onTogglePin: () => widget.onTogglePin(widget.message),
    onResolveAlert: widget.onResolveAlert == null
        ? null
        : (action) => unawaited(widget.onResolveAlert!(widget.message, action)),
    onReport: widget.onReport == null
        ? null
        : () => widget.onReport!(widget.message),
    onDelete: _confirmDelete,
    onMore: (position) => unawaited(_openContextMenu(context, position)),
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
