import 'package:flutter/foundation.dart';

import '../domain/attachment_download.dart';
import '../domain/chat_models.dart';

enum AttachmentDownloadPhase { idle, downloading, saved, failed }

final class AttachmentDownloadController extends ChangeNotifier {
  AttachmentDownloadController({
    required MessageAttachment attachment,
    required AttachmentDownloadService service,
  }) : this._(attachment, service);

  AttachmentDownloadController._(this.attachment, this._service);

  final MessageAttachment attachment;
  final AttachmentDownloadService _service;

  AttachmentDownloadPhase _phase = AttachmentDownloadPhase.idle;
  AttachmentDownloadCancellation? _cancellation;
  AttachmentDownloadProgress? _progress;
  int _generation = 0;
  bool _disposed = false;

  AttachmentDownloadPhase get phase => _phase;
  AttachmentDownloadProgress? get progress => _progress;
  bool get isDownloading => _phase == AttachmentDownloadPhase.downloading;

  Future<AttachmentDownloadResult?> save() async {
    if (_disposed || isDownloading) return null;
    final cancellation = AttachmentDownloadCancellation();
    final generation = ++_generation;
    _cancellation = cancellation;
    _phase = AttachmentDownloadPhase.downloading;
    _progress = null;
    notifyListeners();
    try {
      final result = await _service.save(
        attachment,
        cancellation: cancellation,
        onProgress: (progress) {
          if (_disposed || generation != _generation) return;
          _progress = progress;
          notifyListeners();
        },
      );
      if (_disposed || generation != _generation) return null;
      _phase = result == null
          ? AttachmentDownloadPhase.idle
          : AttachmentDownloadPhase.saved;
      _progress = null;
      _cancellation = null;
      notifyListeners();
      return result;
    } on Object {
      if (_disposed || generation != _generation) return null;
      _phase = AttachmentDownloadPhase.failed;
      _progress = null;
      _cancellation = null;
      notifyListeners();
      return null;
    }
  }

  void cancel() {
    if (_disposed || !isDownloading) return;
    _generation++;
    _cancellation?.cancel();
    _cancellation = null;
    _progress = null;
    _phase = AttachmentDownloadPhase.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancellation?.cancel();
    _cancellation = null;
    super.dispose();
  }
}
