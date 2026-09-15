import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../domain/attachment_download.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import '../attachment_download_controller.dart';
import 'attachment_download_button.dart';
import 'image_attachment_viewer.dart';
import 'native_inline_video_player.dart';
import 'native_voice_message_player.dart';
import 'user_settings_scope.dart';

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
    // A spoiler arrives as the name alone, so it is covered until the reader
    // asks to see it, the same reveal the message text's spoilers use.
    if (_attachment.isSpoiler) {
      return _SpoilerAttachment(attachment: _attachment, child: _revealed());
    }
    return _revealed();
  }

  Widget _revealed() {
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

/// One attachment the sender tagged as a spoiler, covered until the reader
/// asks to see it.
///
/// The tag is the filename prefix Discord's convention puts there, so this
/// cover is the whole difference between a spoiler and an ordinary
/// attachment: underneath it, the attachment renders exactly as it always
/// did.
class _SpoilerAttachment extends StatefulWidget {
  const _SpoilerAttachment({required this.attachment, required this.child});

  final MessageAttachment attachment;
  final Widget child;

  @override
  State<_SpoilerAttachment> createState() => _SpoilerAttachmentState();
}

class _SpoilerAttachmentState extends State<_SpoilerAttachment> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) => _revealed
      ? widget.child
      : Semantics(
          button: true,
          label: 'Reveal spoiler',
          child: InkWell(
            key: const ValueKey('attachment-spoiler-cover'),
            onTap: () => setState(() => _revealed = true),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 210,
              height: 58,
              decoration: BoxDecoration(
                color: context.surfaces.muted,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 18,
                    color: context.surfaces.canvas,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Spoiler',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.surfaces.canvas,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
}

/// Where preview bytes live between runs.
///
/// Bounded by how many previews are kept rather than by the space they take,
/// because the cache manager counts entries and not bytes. That works here
/// because the address they are fetched from already asks the proxy for a
/// preview-sized file, so one entry is tens of kilobytes rather than the
/// original photo, and this many of them land somewhere under half a gigabyte.
/// Discord bounds the same thing the same way: its cache is whatever Chromium
/// keeps, and what it controls is asking for a resized image in the first
/// place.
///
/// The stale period runs from last use, not from download, so a preview goes
/// only once it has been left alone for a fortnight. Losing one costs a single
/// small request the next time it is scrolled past.
class _PreviewCache extends CacheManager with ImageCacheManager {
  _PreviewCache._()
    : super(
        Config(
          _storeKey,
          stalePeriod: const Duration(days: 14),
          maxNrOfCacheObjects: 4000,
        ),
      );

  static const _storeKey = 'flucord_attachment_previews';

  static final _PreviewCache instance = _PreviewCache._();
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
    CachedNetworkImageProvider(
      // The account's autoplay answer, read here so the flag from any
      // device redraws the preview. A GIF the account keeps still is asked
      // for as a png, which is the proxy's first frame.
      _previewUrl(
        attachment,
        width: width,
        height: height,
        playsGifs: UserSettingsScope.displayOf(context).playsGifs,
      ),
      cacheManager: _PreviewCache.instance,
    ),
    width: width,
    height: height,
    policy: ResizeImagePolicy.fit,
  );
}

String _previewUrl(
  MessageAttachment attachment, {
  required int width,
  required int height,
  required bool playsGifs,
}) {
  final proxy = Uri.tryParse(attachment.proxyUrl ?? '');
  if (proxy == null || !proxy.hasAuthority) {
    return playsGifs || !_looksLikeGif(attachment)
        ? attachment.url
        : _stillFrameOf(attachment.url);
  }
  final query = {
    ...proxy.queryParameters,
    'width': '$width',
    'height': '$height',
    if (!playsGifs && _looksLikeGif(attachment)) 'format': 'png',
  };
  return proxy.replace(queryParameters: query).toString();
}

/// Whether the attachment is a moving picture, judged from the filename the
/// sender's client reported. The proxy honours the extension it is given.
bool _looksLikeGif(MessageAttachment attachment) =>
    attachment.fileName.toLowerCase().endsWith('.gif');

/// The first frame of a cdn GIF, which the cdn serves as the webp form.
String _stillFrameOf(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || !parsed.path.endsWith('.gif')) return url;
  return parsed
      .replace(
        path: parsed.path.replaceRange(parsed.path.length - 4, null, '.webp'),
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
                  // A hairline on the clipped edge. Painted over the image, so
                  // a light picture still reads against a light background.
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.black.withValues(alpha: 0.1)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
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
