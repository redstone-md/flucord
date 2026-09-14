import 'package:flutter/material.dart';

import '../../domain/attachment_download.dart';
import '../../domain/chat_models.dart';
import '../attachment_download_controller.dart';
import 'image_attachment_viewer.dart';
import 'message_attachment_view.dart';

class MessageAttachmentGallery extends StatefulWidget {
  const MessageAttachmentGallery({
    required this.attachments,
    this.downloadService,
    this.rendersMedia = true,
    super.key,
  });

  final List<MessageAttachment> attachments;
  final AttachmentDownloadService? downloadService;

  /// Whether image, video and audio attachments render inline.
  ///
  /// Turning inline media off must not hide the attachment: a file still
  /// arrived and the user still needs its name, size and download control.
  /// Suppressing the whole gallery would make ordinary file attachments
  /// disappear from the conversation entirely.
  final bool rendersMedia;

  @override
  State<MessageAttachmentGallery> createState() =>
      _MessageAttachmentGalleryState();
}

class _MessageAttachmentGalleryState extends State<MessageAttachmentGallery> {
  final Map<String, AttachmentDownloadController> _controllers = {};
  final Map<String, String> _signatures = {};

  @override
  void initState() {
    super.initState();
    _synchronizeControllers();
  }

  @override
  void didUpdateWidget(covariant MessageAttachmentGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloadService != widget.downloadService) {
      _disposeAllControllers();
      _synchronizeControllers();
    } else if (oldWidget.attachments != widget.attachments) {
      _synchronizeControllers();
    }
  }

  @override
  void dispose() {
    _disposeAllControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageGallery = List<ImageAttachmentViewerEntry>.unmodifiable(
      widget.attachments
          .where(
            (attachment) => attachment.isImage && attachment.url.isNotEmpty,
          )
          .map(
            (attachment) => ImageAttachmentViewerEntry(
              attachment: attachment,
              downloadController: _controllers[attachment.id],
            ),
          ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final attachment in widget.attachments)
          Padding(
            key: ValueKey('message-attachment-${attachment.id}'),
            padding: const EdgeInsets.only(top: 7),
            child: MessageAttachmentView(
              attachment: attachment,
              downloadController: _controllers[attachment.id],
              imageGallery: imageGallery,
              rendersMedia: widget.rendersMedia,
            ),
          ),
      ],
    );
  }

  void _synchronizeControllers() {
    final service = widget.downloadService;
    if (service == null) {
      _disposeAllControllers();
      return;
    }
    final desired = <String, MessageAttachment>{
      for (final attachment in widget.attachments)
        if (AttachmentDownloadController.supports(attachment, service))
          attachment.id: attachment,
    };
    for (final id in _controllers.keys.toList(growable: false)) {
      final attachment = desired[id];
      if (attachment == null || _signatures[id] != _signature(attachment)) {
        _controllers.remove(id)?.dispose();
        _signatures.remove(id);
      }
    }
    for (final MapEntry(key: id, value: attachment) in desired.entries) {
      if (_controllers.containsKey(id)) continue;
      _controllers[id] = AttachmentDownloadController(
        attachment: attachment,
        service: service,
      );
      _signatures[id] = _signature(attachment);
    }
  }

  void _disposeAllControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _signatures.clear();
  }

  static String _signature(MessageAttachment attachment) =>
      '${attachment.url}\u0000${attachment.fileName}\u0000${attachment.size}';
}
