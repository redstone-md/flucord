import 'chat_models.dart';

typedef AttachmentDownloadProgressCallback =
    void Function(AttachmentDownloadProgress progress);

final class AttachmentDownloadProgress {
  const AttachmentDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0, 1);
  }
}

final class AttachmentDownloadResult {
  const AttachmentDownloadResult({
    required this.path,
    required this.bytesWritten,
  });

  final String path;
  final int bytesWritten;
}

final class AttachmentDownloadCancellation {
  bool _isCancelled = false;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final listeners = _listeners.toList(growable: false);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void Function() listen(void Function() listener) {
    if (_isCancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

abstract interface class AttachmentDownloadService {
  Future<AttachmentDownloadResult?> save(
    MessageAttachment attachment, {
    required AttachmentDownloadCancellation cancellation,
    required AttachmentDownloadProgressCallback onProgress,
  });
}
