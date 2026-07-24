import 'package:flutter/material.dart';

import '../../theme/flucord_theme.dart';
import '../attachment_download_controller.dart';

class AttachmentDownloadButton extends StatelessWidget {
  const AttachmentDownloadButton({
    required this.controller,
    this.overlaid = false,
    this.keyPrefix = 'attachment',
    super.key,
  });

  final AttachmentDownloadController controller;
  final bool overlaid;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Container(
      width: 30,
      height: 30,
      decoration: overlaid
          ? BoxDecoration(
              color: context.surfaces.surface.withValues(alpha: 0.94),
              border: Border.all(color: context.surfaces.border),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: IconButton(
        key: ValueKey('$_actionName-$keyPrefix-${controller.attachment.id}'),
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
        padding: EdgeInsets.zero,
        onPressed: controller.isDownloading
            ? controller.cancel
            : () => _save(context),
        tooltip: _tooltip,
        icon: _icon(context),
      ),
    ),
  );

  Future<void> _save(BuildContext context) async {
    final result = await controller.save();
    if (!context.mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${controller.attachment.fileName}')),
      );
    } else if (controller.phase == AttachmentDownloadPhase.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save ${controller.attachment.fileName}.'),
        ),
      );
    }
  }

  String get _actionName => switch (controller.phase) {
    AttachmentDownloadPhase.idle => 'download',
    AttachmentDownloadPhase.downloading => 'cancel-download',
    AttachmentDownloadPhase.saved => 'save-again',
    AttachmentDownloadPhase.failed => 'retry-download',
  };

  String get _tooltip => switch (controller.phase) {
    AttachmentDownloadPhase.idle => 'Save attachment',
    AttachmentDownloadPhase.downloading => 'Cancel download',
    AttachmentDownloadPhase.saved => 'Saved · save again',
    AttachmentDownloadPhase.failed => 'Download failed · retry',
  };

  Widget _icon(BuildContext context) => switch (controller.phase) {
    AttachmentDownloadPhase.idle => const Icon(
      Icons.download_outlined,
      size: 17,
    ),
    AttachmentDownloadPhase.downloading => SizedBox.square(
      dimension: 15,
      child: CircularProgressIndicator(
        value: controller.progress?.fraction,
        strokeWidth: 2,
      ),
    ),
    AttachmentDownloadPhase.saved => const Icon(
      Icons.check_rounded,
      size: 17,
      color: FlucordColors.success,
    ),
    AttachmentDownloadPhase.failed => Icon(
      Icons.refresh_rounded,
      size: 17,
      color: Theme.of(context).colorScheme.error,
    ),
  };
}
