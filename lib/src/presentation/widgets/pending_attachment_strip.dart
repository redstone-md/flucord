import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

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
      borderRadius: FlucordRadius.small,
    ),
    child: Row(
      children: [
        FlucordIcon(
          attachment.isSpoiler ? FlucordIcons.hidden : FlucordIcons.file,
          size: 18,
          color: context.surfaces.muted,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            attachment.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: FlucordType.caption),
          ),
        ),
        if (onToggleSpoiler != null)
          IconButton(
            key: ValueKey('toggle-spoiler-${attachment.path}'),
            onPressed: onToggleSpoiler,
            icon: FlucordIcon(
              attachment.isSpoiler ? FlucordIcons.hidden : FlucordIcons.visible,
              size: 15,
            ),
            tooltip: attachment.isSpoiler
                ? 'Remove spoiler tag'
                : 'Mark as spoiler',
          ),
        IconButton(
          onPressed: onRemove,
          icon: const FlucordIcon(FlucordIcons.clear, size: 15),
          tooltip: 'Remove attachment',
        ),
      ],
    ),
  );
}
