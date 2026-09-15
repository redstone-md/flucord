import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

class PendingAttachmentStrip extends StatelessWidget {
  const PendingAttachmentStrip({
    required this.attachments,
    required this.onRemove,
    this.onToggleSpoiler,
    this.enabled = true,
    super.key,
  });

  final List<PendingAttachment> attachments;
  final ValueChanged<int> onRemove;

  /// Tags one file as a spoiler, or null where the surface attaching files
  /// offers no tagging.
  final ValueChanged<int>? onToggleSpoiler;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: attachments.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) => _PendingAttachmentTile(
        attachment: attachments[index],
        onRemove: enabled ? () => onRemove(index) : null,
        onToggleSpoiler: enabled && onToggleSpoiler != null
            ? () => onToggleSpoiler!(index)
            : null,
      ),
    ),
  );
}

class _PendingAttachmentTile extends StatelessWidget {
  const _PendingAttachmentTile({
    required this.attachment,
    this.onRemove,
    this.onToggleSpoiler,
  });

  final PendingAttachment attachment;
  final VoidCallback? onRemove;
  final VoidCallback? onToggleSpoiler;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('pending-attachment-${attachment.path}'),
    width: 190,
    padding: const EdgeInsets.only(left: 10),
    decoration: BoxDecoration(
      color: context.surfaces.inset,
      border: Border.all(color: context.surfaces.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        Icon(
          attachment.isSpoiler
              ? Icons.visibility_off_outlined
              : Icons.insert_drive_file_outlined,
          size: 18,
          color: context.surfaces.muted,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            attachment.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ),
        if (onToggleSpoiler != null)
          IconButton(
            key: ValueKey('toggle-spoiler-${attachment.path}'),
            onPressed: onToggleSpoiler,
            icon: Icon(
              attachment.isSpoiler
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 15,
            ),
            tooltip: attachment.isSpoiler
                ? 'Remove spoiler tag'
                : 'Mark as spoiler',
          ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.close, size: 15),
          tooltip: 'Remove attachment',
        ),
      ],
    ),
  );
}
