import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/discord_snowflake.dart';
import '../../domain/duration_in_words.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'chat_image.dart';
import 'message_attachment_view.dart';

/// One post in a forum or media channel, as Discord's post card draws it.
///
/// A gallery card is led by the post's picture; a list card puts the text
/// first with a small thumbnail beside it. Both end in the same footer: who
/// opened the post, when it last moved, and how many replies it has.
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
    final details = _ForumPostDetails(
      parent: parent,
      post: post,
      starter: starter,
      author: starter == null
          ? null
          : workspace.memberOrNull(starter.authorId)?.displayName,
      tags: parent.availableTags
          .where((tag) => post.appliedTagIds.contains(tag.id))
          .toList(growable: false),
      snippetLines: gallery ? 1 : 2,
    );
    return Material(
      color: context.surfaces.raised,
      borderRadius: FlucordRadius.small,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('forum-post-${post.id}'),
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: context.surfaces.border),
            borderRadius: FlucordRadius.small,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PreviewLoadTrigger(
                postId: post.id,
                shouldLoad: starter == null,
                onLoad: onLoadPreview,
              ),
              if (gallery) ...[
                Expanded(
                  child: _ForumMediaPreview(post: post, attachment: attachment),
                ),
                Padding(padding: const EdgeInsets.all(12), child: details),
              ] else
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: details),
                        if (attachment?.isImage == true) ...[
                          const SizedBox(width: 12),
                          ClipRRect(
                            borderRadius: FlucordRadius.small,
                            child: SizedBox.square(
                              dimension: 72,
                              child: _ForumMediaPreview(
                                post: post,
                                attachment: attachment,
                              ),
                            ),
                          ),
                        ],
                      ],
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

/// The post's picture cropped to fill whatever box it is given, or an icon
/// for a post with no picture.
class _ForumMediaPreview extends StatelessWidget {
  const _ForumMediaPreview({required this.post, required this.attachment});

  final ConversationChannel post;
  final MessageAttachment? attachment;

  @override
  Widget build(BuildContext context) {
    final attachment = this.attachment;
    return KeyedSubtree(
      key: ValueKey('forum-post-media-${post.id}'),
      child: attachment != null && attachment.isImage
          ? LayoutBuilder(
              builder: (context, constraints) => Image(
                image: attachmentPreviewImage(
                  context,
                  attachment,
                  _coverBox(attachment, constraints.biggest),
                ),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                frameBuilder: (context, child, frame, synchronous) =>
                    synchronous || frame != null
                    ? child
                    : const _MediaPlaceholder(icon: FlucordIcons.image),
                errorBuilder: (_, _, _) =>
                    const _MediaPlaceholder(icon: FlucordIcons.brokenImage),
              ),
            )
          : _MediaPlaceholder(
              icon: attachment?.isVideo == true
                  ? FlucordIcons.videoFile
                  : attachment == null
                  ? FlucordIcons.mediaChannel
                  : FlucordIcons.file,
              label: attachment?.fileName,
            ),
    );
  }

  /// The size to fetch and decode at: enough to fill [bounds] once cropped,
  /// and no more.
  static Size _coverBox(MessageAttachment attachment, Size bounds) {
    final width = attachment.width;
    final height = attachment.height;
    if (width == null || height == null || width == 0 || height == 0) {
      return bounds;
    }
    return boxCovering(bounds, width / height);
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.icon, this.label});

  final FlucordIconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return ColoredBox(
      color: context.surfaces.inset,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FlucordIcon(icon, size: 24, color: context.surfaces.muted),
              if (label != null) ...[
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.surfaces.muted,
                    fontSize: FlucordType.caption,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ForumPostDetails extends StatelessWidget {
  const _ForumPostDetails({
    required this.parent,
    required this.post,
    required this.starter,
    required this.author,
    required this.tags,
    required this.snippetLines,
  });

  final ConversationChannel parent;
  final ConversationChannel post;
  final ChatMessage? starter;
  final String? author;
  final List<ForumTag> tags;
  final int snippetLines;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      color: context.surfaces.muted,
      fontSize: FlucordType.caption,
      height: 1.3,
    );
    // The opening message's text, when it has any. A post that opens with
    // only a picture shows no snippet: the picture is its content, and its
    // file name says nothing.
    final snippet = starter?.body.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                post.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.label.strong,
              ),
            ),
            if (post.isLocked)
              FlucordIcon(
                FlucordIcons.lock,
                size: 14,
                color: context.surfaces.muted,
              ),
          ],
        ),
        if (snippet.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            snippet,
            maxLines: snippetLines,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              for (final tag in tags.take(2)) ...[
                _PostTag(label: tag.name),
                const SizedBox(width: 4),
              ],
              if (tags.length > 2) Text('+${tags.length - 2}', style: muted),
            ],
          ),
        ],
        const SizedBox(height: 6),
        _ForumPostFooter(post: post, author: author, style: muted),
      ],
    );
  }
}

/// Who opened the post, when it last moved, and how many replies it holds.
class _ForumPostFooter extends StatelessWidget {
  const _ForumPostFooter({
    required this.post,
    required this.author,
    required this.style,
  });

  final ConversationChannel post;
  final String? author;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final activity = _lastActivity();
    final count = post.messageCount;
    return Row(
      children: [
        Expanded(
          child: Text(
            [?author, ?activity].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          FlucordIcon(
            FlucordIcons.forum,
            size: 14,
            color: context.surfaces.muted,
          ),
          const SizedBox(width: 4),
          Text('$count', style: style),
        ],
      ],
    );
  }

  /// How long ago the post last moved: its newest message, else its opening.
  String? _lastActivity() {
    final at = DiscordSnowflake.createdAt(post.lastMessageId ?? post.id);
    if (at == null) return null;
    final ago = DateTime.now().toUtc().difference(at);
    if (ago < const Duration(minutes: 1)) return 'just now';
    return '${durationInWords(ago)} ago';
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
      borderRadius: FlucordRadius.small,
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: FlucordTextRole.caption.strong,
    ),
  );
}
