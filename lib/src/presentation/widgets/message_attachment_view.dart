import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'native_inline_video_player.dart';

class MessageAttachmentView extends StatelessWidget {
  const MessageAttachmentView({
    required this.attachment,
    this.inlineVideoBuilder = buildNativeInlineVideo,
    super.key,
  });

  final MessageAttachment attachment;
  final InlineVideoBuilder inlineVideoBuilder;

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage && attachment.url.isNotEmpty) {
      return _ImageAttachment(attachment: attachment);
    }
    if (attachment.isVideo && attachment.url.isNotEmpty) {
      final ratio = attachment.width != null && attachment.height != null
          ? attachment.width! / attachment.height!
          : 16 / 9;
      return inlineVideoBuilder(
        key: ValueKey('attachment-video-${attachment.id}'),
        url: attachment.url,
        aspectRatio: ratio,
      );
    }
    return _FileAttachment(attachment: attachment);
  }
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.attachment});

  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final ratio = attachment.width != null && attachment.height != null
        ? attachment.width! / attachment.height!
        : 16 / 9;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 280),
      child: AspectRatio(
        aspectRatio: ratio.clamp(0.7, 2.2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            attachment.url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _FileAttachment(attachment: attachment),
          ),
        ),
      ),
    );
  }
}

class _FileAttachment extends StatelessWidget {
  const _FileAttachment({required this.attachment});

  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.surfaces.inset,
          border: Border.all(color: context.surfaces.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 22,
              color: context.surfaces.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatBytes(attachment.size),
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
