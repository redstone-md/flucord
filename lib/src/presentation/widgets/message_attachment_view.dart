import 'package:flutter/material.dart';

import '../../domain/attachment_download.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'native_inline_video_player.dart';
import 'native_voice_message_player.dart';

enum _AttachmentTransferState { idle, downloading, saved, failed }

class MessageAttachmentView extends StatefulWidget {
  const MessageAttachmentView({
    required this.attachment,
    this.downloadService,
    this.inlineVideoBuilder = buildNativeInlineVideo,
    this.inlineVoiceBuilder = buildNativeVoiceMessage,
    super.key,
  });

  final MessageAttachment attachment;
  final AttachmentDownloadService? downloadService;
  final InlineVideoBuilder inlineVideoBuilder;
  final InlineVoiceBuilder inlineVoiceBuilder;

  @override
  State<MessageAttachmentView> createState() => _MessageAttachmentViewState();
}

class _MessageAttachmentViewState extends State<MessageAttachmentView> {
  _AttachmentTransferState _transferState = _AttachmentTransferState.idle;
  AttachmentDownloadCancellation? _cancellation;
  AttachmentDownloadProgress? _progress;
  int _generation = 0;

  MessageAttachment get _attachment => widget.attachment;
  bool get _canDownload {
    final uri = Uri.tryParse(_attachment.url);
    return widget.downloadService != null &&
        uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'https' || uri.scheme == 'http');
  }

  @override
  void didUpdateWidget(covariant MessageAttachmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.url != widget.attachment.url) {
      _cancelTransfer(updateUi: false);
      _transferState = _AttachmentTransferState.idle;
      _progress = null;
    }
  }

  @override
  void dispose() {
    _cancelTransfer(updateUi: false);
    super.dispose();
  }

  Future<void> _saveAttachment() async {
    final service = widget.downloadService;
    if (service == null ||
        _transferState == _AttachmentTransferState.downloading) {
      return;
    }
    final cancellation = AttachmentDownloadCancellation();
    final generation = ++_generation;
    _cancellation = cancellation;
    setState(() {
      _transferState = _AttachmentTransferState.downloading;
      _progress = null;
    });
    try {
      final result = await service.save(
        _attachment,
        cancellation: cancellation,
        onProgress: (progress) {
          if (!mounted || generation != _generation) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _transferState = result == null
            ? _AttachmentTransferState.idle
            : _AttachmentTransferState.saved;
        _progress = null;
        _cancellation = null;
      });
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${_attachment.fileName}')),
        );
      }
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _transferState = _AttachmentTransferState.failed;
        _progress = null;
        _cancellation = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save ${_attachment.fileName}.')),
      );
    }
  }

  void _cancelTransfer({bool updateUi = true}) {
    _generation++;
    _cancellation?.cancel();
    _cancellation = null;
    _progress = null;
    if (updateUi && mounted) {
      setState(() => _transferState = _AttachmentTransferState.idle);
    }
  }

  @override
  Widget build(BuildContext context) {
    late final Widget content;
    if (_attachment.isImage && _attachment.url.isNotEmpty) {
      content = _ImageAttachment(attachment: _attachment);
    } else if (_attachment.isVideo && _attachment.url.isNotEmpty) {
      final ratio = _attachment.width != null && _attachment.height != null
          ? _attachment.width! / _attachment.height!
          : 16 / 9;
      content = widget.inlineVideoBuilder(
        key: ValueKey('attachment-video-${_attachment.id}'),
        url: _attachment.url,
        aspectRatio: ratio,
      );
    } else if (_attachment.isAudio && _attachment.url.isNotEmpty) {
      content = widget.inlineVoiceBuilder(
        key: ValueKey('attachment-audio-${_attachment.id}'),
        url: _attachment.url,
        duration: _attachment.duration,
        waveform: _attachment.waveform,
      );
      if (!_canDownload) return content;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 370),
        child: Row(
          children: [
            Expanded(child: content),
            const SizedBox(width: 4),
            _transferButton(overlaid: false),
          ],
        ),
      );
    } else {
      return _FileAttachment(
        attachment: _attachment,
        trailing: _canDownload ? _transferButton(overlaid: false) : null,
      );
    }
    if (!_canDownload) return content;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        Positioned(top: 6, right: 6, child: _transferButton(overlaid: true)),
      ],
    );
  }

  Widget _transferButton({required bool overlaid}) => Container(
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
      key: ValueKey('$_transferActionName-attachment-${_attachment.id}'),
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      onPressed: _transferState == _AttachmentTransferState.downloading
          ? _cancelTransfer
          : _saveAttachment,
      tooltip: _transferTooltip,
      icon: _transferIcon,
    ),
  );

  String get _transferActionName => switch (_transferState) {
    _AttachmentTransferState.idle => 'download',
    _AttachmentTransferState.downloading => 'cancel-download',
    _AttachmentTransferState.saved => 'save-again',
    _AttachmentTransferState.failed => 'retry-download',
  };

  String get _transferTooltip => switch (_transferState) {
    _AttachmentTransferState.idle => 'Save attachment',
    _AttachmentTransferState.downloading => 'Cancel download',
    _AttachmentTransferState.saved => 'Saved · save again',
    _AttachmentTransferState.failed => 'Download failed · retry',
  };

  Widget get _transferIcon => switch (_transferState) {
    _AttachmentTransferState.idle => const Icon(
      Icons.download_outlined,
      size: 17,
    ),
    _AttachmentTransferState.downloading => SizedBox.square(
      dimension: 15,
      child: CircularProgressIndicator(
        value: _progress?.fraction,
        strokeWidth: 2,
      ),
    ),
    _AttachmentTransferState.saved => const Icon(
      Icons.check_rounded,
      size: 17,
      color: FlucordColors.success,
    ),
    _AttachmentTransferState.failed => Icon(
      Icons.refresh_rounded,
      size: 17,
      color: Theme.of(context).colorScheme.error,
    ),
  };
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
  const _FileAttachment({required this.attachment, this.trailing});

  final MessageAttachment attachment;
  final Widget? trailing;

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
            if (trailing case final action?) ...[
              const SizedBox(width: 8),
              action,
            ],
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
