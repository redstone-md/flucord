import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/discord_social_dm_controller.dart';
import '../../domain/discord_social_dm.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'destructive_confirmation.dart';
import 'flucord_icon_button.dart';
import 'message_timestamp.dart';
import 'recessed_field.dart';

/// One message of a native DM, laid out like a server message: a 40 px
/// avatar, the name and time on one line, and the text under them. Your own
/// messages get an edit and delete bar on hover.
class DiscordSocialDmMessageRow extends StatefulWidget {
  const DiscordSocialDmMessageRow({
    required this.controller,
    required this.message,
    super.key,
  });

  final DiscordSocialDmController controller;
  final DiscordSocialDmMessage message;

  @override
  State<DiscordSocialDmMessageRow> createState() =>
      _DiscordSocialDmMessageRowState();
}

class _DiscordSocialDmMessageRowState extends State<DiscordSocialDmMessageRow> {
  // The server message row's sizes (FLUCORD-73).
  static const _groupGap = 10.0;
  static const _inline = 16.0;
  static const _block = 4.0;
  static const _avatarSize = 40.0;
  static const _avatarGap = 12.0;
  static const _nameRowHeight = 18.0;
  static const _barRise = 16.0;
  static const _hoverAlpha = 0.025;

  TextEditingController? _editor;
  bool _hovered = false;
  bool _editing = false;

  @override
  void didUpdateWidget(DiscordSocialDmMessageRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.message.content != widget.message.content) {
      _editor?.text = widget.message.content;
    }
  }

  @override
  void dispose() {
    _editor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final message = widget.message;
    final author = message.authorDisplayName.isEmpty
        ? (message.authoredByCurrentUser ? 'You' : 'Unknown user')
        : message.authorDisplayName;
    final mutating = widget.controller.isMutatingMessage(message.id);
    final actionError = widget.controller.messageActionErrorFor(message.id);
    return Padding(
      padding: const EdgeInsets.only(top: _groupGap),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              color: _hovered
                  ? surfaces.text.withValues(alpha: _hoverAlpha)
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(
                horizontal: _inline,
                vertical: _block,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InitialAvatar(
                    key: ValueKey('social-dm-avatar-${message.id}'),
                    name: author,
                    size: _avatarSize,
                  ),
                  const SizedBox(width: _avatarGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MessageMetadata(
                          message: message,
                          author: author,
                          height: _nameRowHeight,
                        ),
                        if (_editing)
                          _buildEditor(context, mutating)
                        else
                          SelectableText(
                            message.content,
                            style: FlucordTextRole.body.style.copyWith(
                              color: surfaces.bodyText,
                            ),
                          ),
                        if (actionError != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Message action failed ($actionError)',
                            key: ValueKey(
                              'social-dm-action-error-${message.id}',
                            ),
                            style: FlucordTextRole.caption.style.copyWith(
                              color: surfaces.errorText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (message.authoredByCurrentUser &&
                (_hovered || _editing || mutating))
              PositionedDirectional(
                end: _inline,
                top: -_barRise,
                child: _MessageActions(
                  messageId: message.id,
                  editing: _editing,
                  mutating: mutating,
                  onEdit: _beginEdit,
                  onDelete: () => _confirmDelete(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context, bool mutating) {
    final surfaces = context.surfaces;
    final editor = _editor!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _cancelEdit,
            const SingleActivator(LogicalKeyboardKey.enter): _saveEdit,
          },
          child: TextField(
            key: ValueKey('social-dm-edit-field-${widget.message.id}'),
            controller: editor,
            autofocus: true,
            enabled: !mutating,
            minLines: 1,
            maxLines: 8,
            maxLength: 2000,
            style: FlucordTextRole.body.style.copyWith(color: surfaces.text),
            decoration:
                recessedFieldDecoration(
                  context,
                  borderRadius: FlucordRadius.control,
                ).copyWith(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  counterText: '',
                ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Escape to cancel · Enter to save',
          style: FlucordTextRole.caption.style.copyWith(
            color: surfaces.captionText,
          ),
        ),
      ],
    );
  }

  void _beginEdit() {
    _editor ??= TextEditingController(text: widget.message.content);
    _editor!.text = widget.message.content;
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    if (!_editing || widget.controller.isMutatingMessage(widget.message.id)) {
      return;
    }
    setState(() => _editing = false);
  }

  Future<void> _saveEdit() async {
    final content = _editor?.text ?? '';
    if (content.trim().isEmpty || content.length > 2000) return;
    final saved = await widget.controller.editMessage(
      widget.message.conversationUserId,
      widget.message.id,
      content,
    );
    if (saved && mounted) setState(() => _editing = false);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete message?',
      message: widget.message.content,
      confirmLabel: 'Delete',
      confirmKey: ValueKey('social-dm-confirm-delete-${widget.message.id}'),
    );
    if (!confirmed || !mounted) return;
    await widget.controller.deleteMessage(
      widget.message.conversationUserId,
      widget.message.id,
    );
  }
}

/// The author's first letter on a round tile. The native SDK gives a
/// message no avatar picture.
class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.name, required this.size, super.key});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: surfaces.raised, shape: BoxShape.circle),
      child: Text(
        name.characters.first.toUpperCase(),
        style: FlucordTextRole.heading.style.copyWith(color: surfaces.text),
      ),
    );
  }
}

/// The name and the time, on a row whose top meets the avatar's top.
class _MessageMetadata extends StatelessWidget {
  const _MessageMetadata({
    required this.message,
    required this.author,
    required this.height,
  });

  final DiscordSocialDmMessage message;
  final String author;
  final double height;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final caption = FlucordTextRole.caption.style.copyWith(
      color: surfaces.captionText,
    );
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Flexible(
            child: Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FlucordTextRole.heading.style.copyWith(
                height: height / FlucordTextRole.heading.size,
                color: surfaces.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          MessageTimeLabel(message.sentAt, style: caption),
          if (message.editedAt != null) ...[
            const SizedBox(width: 4),
            Text('(edited)', style: caption),
          ],
        ],
      ),
    );
  }
}

/// The bar over your own message: edit and delete, or a spinner while one
/// of them runs.
class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.messageId,
    required this.editing,
    required this.mutating,
    required this.onEdit,
    required this.onDelete,
  });

  static const _inset = 2.0;

  final String messageId;
  final bool editing;
  final bool mutating;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Material(
      color: surfaces.raised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: surfaces.border),
        borderRadius: FlucordRadius.control,
      ),
      child: Padding(
        padding: const EdgeInsets.all(_inset),
        child: mutating
            ? const SizedBox.square(
                dimension: FlucordIconButton.size,
                child: Center(
                  child: SizedBox.square(
                    dimension: FlucordIconButton.iconSize,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!editing)
                    FlucordIconButton(
                      key: ValueKey('social-dm-edit-$messageId'),
                      tooltip: 'Edit message',
                      icon: FlucordIcons.edit,
                      onPressed: onEdit,
                    ),
                  FlucordIconButton(
                    key: ValueKey('social-dm-delete-$messageId'),
                    tooltip: 'Delete message',
                    icon: FlucordIcons.delete,
                    onPressed: onDelete,
                  ),
                ],
              ),
      ),
    );
  }
}
