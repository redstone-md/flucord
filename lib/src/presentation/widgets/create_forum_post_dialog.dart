import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import '../pending_attachment_picker.dart';
import 'pending_attachment_strip.dart';
import 'flucord_dialog.dart';

typedef CreateForumPostCallback =
    Future<bool> Function(
      String name,
      String content,
      List<PendingAttachment> attachments,
      int autoArchiveDurationMinutes,
      List<String> appliedTagIds,
    );

class CreateForumPostDialog extends StatefulWidget {
  const CreateForumPostDialog({
    required this.channel,
    required this.onCreate,
    this.attachmentPicker = const NativePendingAttachmentPicker(),
    super.key,
  });

  final ConversationChannel channel;
  final CreateForumPostCallback onCreate;
  final PendingAttachmentPicker attachmentPicker;

  static Future<bool> show(
    BuildContext context, {
    required ConversationChannel channel,
    required CreateForumPostCallback onCreate,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            CreateForumPostDialog(channel: channel, onCreate: onCreate),
      ) ??
      false;

  @override
  State<CreateForumPostDialog> createState() => _CreateForumPostDialogState();
}

class _CreateForumPostDialogState extends State<CreateForumPostDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final PendingAttachmentSelection _attachments = PendingAttachmentSelection();
  final Set<String> _selectedTagIds = {};
  late int _autoArchiveDurationMinutes;
  bool _isCreating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final preferred = widget.channel.defaultAutoArchiveDurationMinutes;
    _autoArchiveDurationMinutes =
        const {60, 1440, 4320, 10080}.contains(preferred) ? preferred! : 1440;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final content = _contentController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a post title.');
      return;
    }
    if (content.isEmpty && _attachments.isEmpty) {
      setState(() => _error = 'Write a message or attach a file.');
      return;
    }
    setState(() {
      _isCreating = true;
      _error = null;
    });
    final created = await widget.onCreate(
      name,
      content,
      _attachments.items,
      _autoArchiveDurationMinutes,
      _selectedTagIds.toList(growable: false),
    );
    if (!mounted) return;
    if (created) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _isCreating = false;
      _error = 'Could not create the post.';
    });
  }

  Future<void> _pickAttachments() async {
    try {
      final picked = await widget.attachmentPicker.pick();
      if (!mounted || picked.isEmpty) return;
      final reachedLimit = _attachments.merge(picked);
      setState(() {});
      if (reachedLimit) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can attach up to 10 files.')),
        );
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The file picker could not be opened.')),
      );
    }
  }

  void _toggleTag(String tagId, bool selected) {
    if (_isCreating) return;
    setState(() {
      if (selected) {
        if (_selectedTagIds.length < 5) _selectedTagIds.add(tagId);
      } else {
        _selectedTagIds.remove(tagId);
      }
    });
  }

  @override
  Widget build(BuildContext context) => FlucordDialog.frame(
    maxWidth: 520,
    maxHeight: MediaQuery.sizeOf(context).height - 40,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlucordDialogHeader(
            title: 'Create a post',
            icon: widget.channel.kind == ChannelKind.media
                ? FlucordIcons.mediaChannel
                : FlucordIcons.forum,
            onClose: _isCreating ? null : () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('forum-post-name'),
            controller: _nameController,
            autofocus: true,
            enabled: !_isCreating,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Post title',
              hintText: 'What is this about?',
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('forum-post-content'),
            controller: _contentController,
            enabled: !_isCreating,
            minLines: 4,
            maxLines: 7,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'First message',
              hintText: 'Start the discussion',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                key: const ValueKey('forum-post-add-attachments'),
                onPressed: _isCreating ? null : _pickAttachments,
                icon: const FlucordIcon(FlucordIcons.attachment, size: 16),
                label: const Text('Add files'),
              ),
              const SizedBox(width: 10),
              Text(
                '${_attachments.items.length}/${PendingAttachment.maxCount}',
                style: TextStyle(
                  color: context.surfaces.muted,
                  fontSize: FlucordType.caption,
                ),
              ),
            ],
          ),
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            PendingAttachmentStrip(
              attachments: _attachments.items,
              enabled: !_isCreating,
              onRemove: (index) => setState(() => _attachments.removeAt(index)),
            ),
          ],
          if (widget.channel.availableTags.isNotEmpty) ...[
            const SizedBox(height: 8),
            _FieldLabel(label: 'TAGS', detail: '${_selectedTagIds.length}/5'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in widget.channel.availableTags)
                  FilterChip(
                    key: ValueKey('forum-post-tag-${tag.id}'),
                    selected: _selectedTagIds.contains(tag.id),
                    onSelected: _isCreating
                        ? null
                        : (selected) => _toggleTag(tag.id, selected),
                    avatar: tag.emojiName == null
                        ? null
                        : Text(
                            tag.emojiName!,
                            style: const TextStyle(
                              fontSize: FlucordType.caption,
                            ),
                          ),
                    label: Text(tag.name),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const _FieldLabel(label: 'AUTO-ARCHIVE'),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              key: const ValueKey('forum-post-auto-archive'),
              segments: const [
                ButtonSegment(value: 60, label: Text('1 hour')),
                ButtonSegment(value: 1440, label: Text('24 hours')),
                ButtonSegment(value: 4320, label: Text('3 days')),
                ButtonSegment(value: 10080, label: Text('1 week')),
              ],
              selected: {_autoArchiveDurationMinutes},
              showSelectedIcon: false,
              onSelectionChanged: _isCreating
                  ? null
                  : (selection) => setState(
                      () => _autoArchiveDurationMinutes = selection.single,
                    ),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8),
                ),
                textStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: FlucordType.caption),
                ),
              ),
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            _ForumDialogError(message: error),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isCreating ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('create-forum-post-confirm'),
                onPressed: _isCreating ? null : _submit,
                icon: _isCreating
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const FlucordIcon(FlucordIcons.newPost, size: 16),
                label: const Text('Create post'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.detail});

  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label,
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: FlucordType.caption,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (detail != null) ...[
        const Spacer(),
        Text(
          detail!,
          style: TextStyle(
            color: context.surfaces.muted,
            fontSize: FlucordType.caption,
          ),
        ),
      ],
    ],
  );
}

class _ForumDialogError extends StatelessWidget {
  const _ForumDialogError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      FlucordIcon(
        FlucordIcons.error,
        size: 15,
        color: Theme.of(context).colorScheme.error,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: FlucordType.caption,
          ),
        ),
      ),
    ],
  );
}
