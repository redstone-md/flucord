import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/attachment_download.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import '../attachment_download_controller.dart';
import 'attachment_download_button.dart';
import 'image_attachment_viewer.dart';
import 'native_inline_video_player.dart';
import 'native_voice_message_player.dart';

class MessageAttachmentView extends StatefulWidget {
  const MessageAttachmentView({
    required this.attachment,
    this.downloadService,
    this.downloadController,
    this.imageGallery = const [],
    this.rendersMedia = true,
    this.inlineVideoBuilder = buildNativeInlineVideo,
    this.inlineVoiceBuilder = buildNativeVoiceMessage,
    super.key,
  }) : assert(downloadService == null || downloadController == null);

  /// The box an inline image preview is drawn in, and so the size it is
  /// fetched and decoded at. Kept here because it is the one place the
  /// preview's cost is decided.
  static const Size previewSize = Size(420, 280);

  final MessageAttachment attachment;
  final AttachmentDownloadService? downloadService;
  final AttachmentDownloadController? downloadController;
  final List<ImageAttachmentViewerEntry> imageGallery;

  /// Whether this attachment renders as inline media. When false it still
  /// renders — as the file row, with its name, size and download control —
  /// because the attachment exists either way.
  final bool rendersMedia;
  final InlineVideoBuilder inlineVideoBuilder;
  final InlineVoiceBuilder inlineVoiceBuilder;

  @override
  State<MessageAttachmentView> createState() => _MessageAttachmentViewState();
}

class _MessageAttachmentViewState extends State<MessageAttachmentView> {
  AttachmentDownloadController? _ownedDownloadController;

  MessageAttachment get _attachment => widget.attachment;
  AttachmentDownloadController? get _downloadController =>
      widget.downloadController ?? _ownedDownloadController;

  @override
  void initState() {
    super.initState();
    _replaceDownloadController();
  }

  bool get _canDownload => _downloadController != null;

  @override
  void didUpdateWidget(covariant MessageAttachmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.url != widget.attachment.url ||
        oldWidget.downloadService != widget.downloadService ||
        oldWidget.downloadController != widget.downloadController) {
      _replaceDownloadController();
    }
  }

  @override
  void dispose() {
    _ownedDownloadController?.dispose();
    super.dispose();
  }

  void _replaceDownloadController() {
    _ownedDownloadController?.dispose();
    _ownedDownloadController = null;
    if (widget.downloadController != null) return;
    final service = widget.downloadService;
    if (!AttachmentDownloadController.supports(_attachment, service)) return;
    _ownedDownloadController = AttachmentDownloadController(
      attachment: _attachment,
      service: service!,
    );
  }

  @override
  Widget build(BuildContext context) {
    late final Widget content;
    // With inline media off every attachment falls through to the file row.
    // The attachment is still there; only its preview is suppressed.
    final media = widget.rendersMedia;
    if (media && _attachment.isImage && _attachment.url.isNotEmpty) {
      content = _ImageAttachment(
        attachment: _attachment,
        onOpen: () => unawaited(
          ImageAttachmentViewer.show(
            context,
            entries: _resolvedImageGallery,
            initialAttachmentId: _attachment.id,
          ),
        ),
      );
    } else if (media && _attachment.isVideo && _attachment.url.isNotEmpty) {
      final ratio = _attachment.width != null && _attachment.height != null
          ? _attachment.width! / _attachment.height!
          : 16 / 9;
      content = widget.inlineVideoBuilder(
        key: ValueKey('attachment-video-${_attachment.id}'),
        url: _attachment.url,
        aspectRatio: ratio,
      );
    } else if (media && _attachment.isAudio && _attachment.url.isNotEmpty) {
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
            _downloadButton(overlaid: false),
          ],
        ),
      );
    } else {
      return _FileAttachment(
        attachment: _attachment,
        trailing: _canDownload ? _downloadButton(overlaid: false) : null,
      );
    }
    if (!_canDownload) return content;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        Positioned(top: 6, right: 6, child: _downloadButton(overlaid: true)),
      ],
    );
  }

  Widget _downloadButton({required bool overlaid}) => AttachmentDownloadButton(
    controller: _downloadController!,
    overlaid: overlaid,
  );

  List<ImageAttachmentViewerEntry> get _resolvedImageGallery {
    final gallery = widget.imageGallery;
    if (gallery.any((entry) => entry.attachment.id == _attachment.id)) {
      return gallery;
    }
    return [
      ImageAttachmentViewerEntry(
        attachment: _attachment,
        downloadController: _downloadController,
      ),
    ];
  }
}

/// The box a preview of this shape is drawn in.
///
/// The aspect ratio decides it: a portrait picture fills the height and stops
/// short of the width, so asking for the full width would fetch pixels that
/// are never drawn.
Size _previewBox(double ratio) {
  final bounds = MessageAttachmentView.previewSize;
  final width = math.min(bounds.width, bounds.height * ratio);
  return Size(width, width / ratio);
}

/// The image a preview draws, fetched and decoded at the size it is shown at.
///
/// Discord's media proxy resizes on request, so a photo taken on a phone costs
/// its thumbnail rather than its original. An attachment Discord did not proxy
/// keeps its own address and is still decoded down, which is the part that
/// keeps a large picture out of the image cache at full size.
ImageProvider _previewImage(
  BuildContext context,
  MessageAttachment attachment,
  Size box,
) {
  final scale = MediaQuery.devicePixelRatioOf(context);
  final width = (box.width * scale).round();
  final height = (box.height * scale).round();
  return ResizeImage(
    NetworkImage(_previewUrl(attachment, width: width, height: height)),
    width: width,
    height: height,
    policy: ResizeImagePolicy.fit,
  );
}

String _previewUrl(
  MessageAttachment attachment, {
  required int width,
  required int height,
}) {
  final proxy = Uri.tryParse(attachment.proxyUrl ?? '');
  if (proxy == null || !proxy.hasAuthority) return attachment.url;
  return proxy
      .replace(
        queryParameters: {
          ...proxy.queryParameters,
          'width': '$width',
          'height': '$height',
        },
      )
      .toString();
}

class _ImageAttachment extends StatelessWidget {
  const _ImageAttachment({required this.attachment, required this.onOpen});

  final MessageAttachment attachment;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ratio =
        (attachment.width != null && attachment.height != null
                ? attachment.width! / attachment.height!
                : 16 / 9)
            .clamp(0.7, 2.2);
    final box = _previewBox(ratio);
    return Semantics(
      button: true,
      label: 'Open image ${attachment.fileName}',
      child: Tooltip(
        message: 'Open image',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey('open-image-attachment-${attachment.id}'),
            onTap: onOpen,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MessageAttachmentView.previewSize.width,
                maxHeight: MessageAttachmentView.previewSize.height,
              ),
              child: AspectRatio(
                aspectRatio: ratio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image(
                    image: _previewImage(context, attachment, box),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) =>
                        _FileAttachment(attachment: attachment),
                  ),
                ),
              ),
            ),
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
