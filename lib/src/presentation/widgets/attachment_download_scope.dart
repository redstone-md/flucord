import 'package:flutter/widgets.dart';

import '../../domain/attachment_download.dart';

/// Publishes the attachment download service to the conversation pane.
///
/// A plain service rather than a listenable, so this is an [InheritedWidget]:
/// downloads report progress through their own callbacks, not notifications.
final class AttachmentDownloadScope extends InheritedWidget {
  const AttachmentDownloadScope({
    required this.service,
    required super.child,
    super.key,
  });

  final AttachmentDownloadService service;

  @override
  bool updateShouldNotify(AttachmentDownloadScope oldWidget) =>
      oldWidget.service != service;

  static AttachmentDownloadService? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AttachmentDownloadScope>()?.service;
}
