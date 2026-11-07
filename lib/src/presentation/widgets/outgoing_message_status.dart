import 'package:flutter/material.dart';

import '../../application/send_failure.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// What a message on its way shows under its text or its voice message: the
/// upload of its files while it sends, or why it failed, with Retry and Delete.
class OutgoingMessageStatus extends StatelessWidget {
  const OutgoingMessageStatus({
    required this.message,
    required this.onRetry,
    required this.onDiscard,
    super.key,
  });

  final OutgoingMessage message;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) => switch (message.delivery) {
    OutgoingSending(:final uploadProgress) =>
      message.attachments.isEmpty
          ? const SizedBox.shrink()
          : _upload(context, uploadProgress),
    OutgoingFailed(:final error) => _failure(context, error),
  };

  Widget _upload(BuildContext context, double? progress) {
    final surfaces = context.surfaces;
    final files = message.attachments;
    final caption = FlucordTextRole.caption.style.copyWith(
      color: surfaces.captionText,
    );
    return Padding(
      key: ValueKey('outgoing-upload-${message.nonce}'),
      padding: const EdgeInsets.only(top: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FlucordIcon(
                  FlucordIcons.upload,
                  size: 16,
                  color: surfaces.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    switch ((message.kind, files)) {
                      (OutgoingVoice(), _) => 'Voice message',
                      (OutgoingText(), [final file]) => file.name,
                      (OutgoingText(), _) => '${files.length} files',
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: caption,
                  ),
                ),
                if (progress != null)
                  Text('${(progress * 100).floor()}%', style: caption),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
              semanticsLabel: 'Uploading',
            ),
          ],
        ),
      ),
    );
  }

  Widget _failure(BuildContext context, Object error) {
    final surfaces = context.surfaces;
    final style = FlucordTextRole.caption.style.copyWith(
      color: surfaces.errorText,
    );
    return Padding(
      key: ValueKey('outgoing-failed-${message.nonce}'),
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FlucordIcon(FlucordIcons.error, size: 16, color: surfaces.danger),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Not sent. ${sendFailureReason(error)}',
                  style: style,
                ),
              ),
            ],
          ),
          _action('outgoing-retry', 'Retry', onRetry),
          _action('outgoing-discard', 'Delete', onDiscard),
        ],
      ),
    );
  }

  Widget _action(String key, String label, VoidCallback onPressed) =>
      TextButton(
        key: ValueKey(key),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: FlucordTextRole.caption.strong,
        ),
        child: Text(label),
      );
}
