import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/discord_social_dm_controller.dart';
import '../../domain/discord_social_dm.dart';
import '../../theme/flucord_theme.dart';

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
    final message = widget.message;
    final author = message.authorDisplayName.isEmpty
        ? (message.authoredByCurrentUser ? 'You' : 'Unknown user')
        : message.authorDisplayName;
    final mutating = widget.controller.isMutatingMessage(message.id);
    final actionError = widget.controller.messageActionErrorFor(message.id);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ColoredBox(
        color: _hovered ? context.surfaces.surface : Colors.transparent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: context.surfaces.raised,
                    child: Text(
                      author.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MessageMetadata(message: message, author: author),
                        const SizedBox(height: 2),
                        if (_editing)
                          _buildEditor(context, mutating)
                        else
                          SelectableText(
                            message.content,
                            style: const TextStyle(fontSize: 13, height: 1.35),
                          ),
                        if (actionError != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Message action failed ($actionError)',
                            key: ValueKey(
                              'social-dm-action-error-${message.id}',
                            ),
                            style: const TextStyle(
                              color: FlucordColors.danger,
                              fontSize: 10,
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
              Positioned(
                right: 4,
                top: -10,
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
            decoration: InputDecoration(
              filled: true,
              fillColor: context.surfaces.inset,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              counterText: '',
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Escape to cancel · Enter to save',
          style: TextStyle(color: context.surfaces.muted, fontSize: 9),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text(
          widget.message.content,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: ValueKey('social-dm-confirm-delete-${widget.message.id}'),
            style: FilledButton.styleFrom(
              backgroundColor: FlucordColors.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.controller.deleteMessage(
      widget.message.conversationUserId,
      widget.message.id,
    );
  }
}

class _MessageMetadata extends StatelessWidget {
  const _MessageMetadata({required this.message, required this.author});

  final DiscordSocialDmMessage message;
  final String author;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          _timestamp(message.sentAt),
          style: TextStyle(color: context.surfaces.muted, fontSize: 9),
        ),
        if (message.editedAt != null) ...[
          const SizedBox(width: 4),
          Text(
            '(edited)',
            style: TextStyle(color: context.surfaces.muted, fontSize: 9),
          ),
        ],
      ],
    );
  }

  static String _timestamp(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $hour:$minute';
  }
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.messageId,
    required this.editing,
    required this.mutating,
    required this.onEdit,
    required this.onDelete,
  });

  final String messageId;
  final bool editing;
  final bool mutating;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.surfaces.raised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: mutating
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!editing)
                  _ActionButton(
                    key: ValueKey('social-dm-edit-$messageId'),
                    tooltip: 'Edit message',
                    icon: Icons.edit_outlined,
                    onPressed: onEdit,
                  ),
                _ActionButton(
                  key: ValueKey('social-dm-delete-$messageId'),
                  tooltip: 'Delete message',
                  icon: Icons.delete_outline,
                  onPressed: onDelete,
                ),
              ],
            ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: context.surfaces.muted),
    );
  }
}
