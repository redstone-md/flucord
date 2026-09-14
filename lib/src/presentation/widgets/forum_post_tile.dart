import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

class ForumPostTile extends StatelessWidget {
  const ForumPostTile({
    required this.workspace,
    required this.parent,
    required this.post,
    required this.gallery,
    required this.onPressed,
    required this.onLoadPreview,
    super.key,
  });

  final ChatWorkspace workspace;
  final ConversationChannel parent;
  final ConversationChannel post;
  final bool gallery;
  final VoidCallback onPressed;
  final VoidCallback onLoadPreview;

  @override
  Widget build(BuildContext context) {
    final starter = _starterMessage();
    final attachment = _previewAttachment(starter);
    final tags = parent.availableTags
        .where((tag) => post.appliedTagIds.contains(tag.id))
        .toList(growable: false);
    return Material(
      color: context.surfaces.raised,
      borderRadius: BorderRadius.circular(5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('forum-post-${post.id}'),
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: context.surfaces.border),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PreviewLoadTrigger(
                postId: post.id,
                shouldLoad: starter == null,
                onLoad: onLoadPreview,
              ),
              if (gallery)
                _ForumMediaPreview(post: post, attachment: attachment),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ForumPostDetails(
                    parent: parent,
                    post: post,
                    starter: starter,
                    attachment: attachment,
                    tags: tags,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ChatMessage? _starterMessage() {
    final messages = workspace.messagesFor(post.id);
    if (messages.isEmpty) return null;
    return messages.reduce(
      (earliest, message) =>
          message.sentAt.isBefore(earliest.sentAt) ? message : earliest,
    );
  }

  static MessageAttachment? _previewAttachment(ChatMessage? message) {
    if (message == null || message.attachments.isEmpty) return null;
    for (final attachment in message.attachments) {
      if (attachment.isImage) return attachment;
    }
    return message.attachments.first;
  }
}

class _PreviewLoadTrigger extends StatefulWidget {
  const _PreviewLoadTrigger({
    required this.postId,
    required this.shouldLoad,
    required this.onLoad,
  });

  final String postId;
  final bool shouldLoad;
  final VoidCallback onLoad;

  @override
  State<_PreviewLoadTrigger> createState() => _PreviewLoadTriggerState();
}

class _PreviewLoadTriggerState extends State<_PreviewLoadTrigger> {
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _PreviewLoadTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.postId != widget.postId) _requested = false;
    _schedule();
  }

  void _schedule() {
    if (!widget.shouldLoad || _requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.shouldLoad) widget.onLoad();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ForumMediaPreview extends StatelessWidget {
  const _ForumMediaPreview({required this.post, required this.attachment});

  final ConversationChannel post;
  final MessageAttachment? attachment;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey('forum-post-media-${post.id}'),
    height: 124,
    child: attachment?.isImage == true && attachment!.url.isNotEmpty
        ? Image.network(
            attachment!.url,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const _MediaPlaceholder(
                    icon: Icons.image_outlined,
                    label: 'Loading preview',
                  ),
            errorBuilder: (_, _, _) => _MediaPlaceholder(
              icon: Icons.broken_image_outlined,
              label: attachment!.fileName,
            ),
          )
        : _MediaPlaceholder(
            icon: attachment?.isVideo == true
                ? Icons.play_circle_outline
                : attachment == null
                ? Icons.perm_media_outlined
                : Icons.insert_drive_file_outlined,
            label: attachment?.fileName ?? 'No media preview',
          ),
  );
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.surfaces.inset,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: context.surfaces.muted),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.surfaces.muted, fontSize: 10),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ForumPostDetails extends StatelessWidget {
  const _ForumPostDetails({
    required this.parent,
    required this.post,
    required this.starter,
    required this.attachment,
    required this.tags,
  });

  final ConversationChannel parent;
  final ConversationChannel post;
  final ChatMessage? starter;
  final MessageAttachment? attachment;
  final List<ForumTag> tags;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            parent.kind == ChannelKind.media
                ? Icons.perm_media_outlined
                : Icons.chat_bubble_outline,
            size: 16,
            color: context.surfaces.muted,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              post.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (post.isLocked)
            Icon(Icons.lock_outline, size: 14, color: context.surfaces.muted),
        ],
      ),
      const SizedBox(height: 7),
      Expanded(
        child: Text(
          _previewText(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.surfaces.muted,
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ),
      if (tags.isNotEmpty)
        Row(
          children: [
            for (final tag in tags.take(2)) ...[
              _PostTag(label: tag.name),
              const SizedBox(width: 4),
            ],
            if (tags.length > 2)
              Text(
                '+${tags.length - 2}',
                style: TextStyle(color: context.surfaces.muted, fontSize: 9),
              ),
          ],
        ),
    ],
  );

  String _previewText() {
    final body = starter?.body.trim();
    if (body?.isNotEmpty == true) return body!;
    if (attachment != null) return attachment!.fileName;
    return post.isArchived ? 'Archived post' : 'Open post';
  }
}

class _PostTag extends StatelessWidget {
  const _PostTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 96),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: context.surfaces.inset,
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
    ),
  );
}
