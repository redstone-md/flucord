import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../domain/attachment_download.dart';
import '../domain/chat_models.dart';

typedef AttachmentHttpClientFactory = HttpClient Function();
typedef AttachmentDownloadClock = DateTime Function();

abstract interface class AttachmentSaveLocationPicker {
  Future<String?> chooseDestination(String suggestedName);
}

final class NativeAttachmentSaveLocationPicker
    implements AttachmentSaveLocationPicker {
  const NativeAttachmentSaveLocationPicker();

  @override
  Future<String?> chooseDestination(String suggestedName) {
    final safeName = sanitizeFileName(suggestedName);
    final extensionIndex = safeName.lastIndexOf('.');
    final extension = extensionIndex > 0 && extensionIndex < safeName.length - 1
        ? safeName.substring(extensionIndex + 1)
        : null;
    return FilePicker.saveFile(
      dialogTitle: 'Save attachment',
      fileName: safeName,
      type: extension == null ? FileType.any : FileType.custom,
      allowedExtensions: extension == null ? null : [extension],
      lockParentWindow: true,
    );
  }

  static String sanitizeFileName(String value) {
    var safe = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    safe = safe.replaceFirst(RegExp(r'[. ]+$'), '');
    if (safe.isEmpty) safe = 'attachment';
    if (RegExp(
      r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(safe)) {
      safe = '_$safe';
    }
    if (safe.length > 180) safe = safe.substring(safe.length - 180);
    return safe;
  }
}

final class NativeAttachmentDownloadService
    implements AttachmentDownloadService {
  NativeAttachmentDownloadService({
    AttachmentSaveLocationPicker? locationPicker,
    AttachmentHttpClientFactory? httpClientFactory,
    AttachmentDownloadClock? clock,
  }) : _locationPicker =
           locationPicker ?? const NativeAttachmentSaveLocationPicker(),
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _clock = clock ?? DateTime.now;

  final AttachmentSaveLocationPicker _locationPicker;
  final AttachmentHttpClientFactory _httpClientFactory;
  final AttachmentDownloadClock _clock;
  int _fileSequence = 0;

  @override
  Future<AttachmentDownloadResult?> save(
    MessageAttachment attachment, {
    required AttachmentDownloadCancellation cancellation,
    required AttachmentDownloadProgressCallback onProgress,
  }) async {
    final uri = Uri.tryParse(attachment.url);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError.value(
        attachment.url,
        'attachment.url',
        'Only absolute HTTP(S) attachment URLs can be downloaded',
      );
    }
    final destinationPath = await _locationPicker.chooseDestination(
      attachment.fileName,
    );
    if (destinationPath == null || cancellation.isCancelled) return null;
    return _download(
      uri,
      destinationPath,
      fallbackSize: attachment.size,
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }

  Future<AttachmentDownloadResult?> _download(
    Uri uri,
    String destinationPath, {
    required int fallbackSize,
    required AttachmentDownloadCancellation cancellation,
    required AttachmentDownloadProgressCallback onProgress,
  }) async {
    final client = _httpClientFactory();
    final stopListening = cancellation.listen(() => client.close(force: true));
    File? partFile;
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Attachment download returned HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final totalBytes = response.contentLength >= 0
          ? response.contentLength
          : fallbackSize > 0
          ? fallbackSize
          : null;
      partFile = await _createSiblingTemporaryFile(destinationPath);
      sink = partFile.openWrite();
      var receivedBytes = 0;
      onProgress(
        AttachmentDownloadProgress(
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
        ),
      );
      await for (final chunk in response) {
        if (cancellation.isCancelled) return null;
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress(
          AttachmentDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (cancellation.isCancelled) return null;
      if (response.contentLength >= 0 &&
          receivedBytes != response.contentLength) {
        throw StateError(
          'Attachment ended at $receivedBytes of ${response.contentLength} bytes',
        );
      }
      await _replaceDestination(partFile, destinationPath);
      partFile = null;
      return AttachmentDownloadResult(
        path: destinationPath,
        bytesWritten: receivedBytes,
      );
    } catch (_) {
      if (cancellation.isCancelled) return null;
      rethrow;
    } finally {
      stopListening();
      client.close(force: true);
      await _closeIgnoringErrors(sink);
      await _deleteIgnoringErrors(partFile);
    }
  }

  Future<File> _createSiblingTemporaryFile(String destinationPath) async {
    final destination = File(destinationPath).absolute;
    await destination.parent.create(recursive: true);
    final stamp = _clock().toUtc().microsecondsSinceEpoch.toRadixString(36);
    while (true) {
      final suffix = _fileSequence++;
      final candidate = File('${destination.path}.flucord-$stamp-$suffix.part');
      if (!await candidate.exists()) return candidate;
    }
  }

  Future<void> _replaceDestination(File part, String destinationPath) async {
    final destination = File(destinationPath).absolute;
    File? backup;
    if (await destination.exists()) {
      backup = File('${part.path}.previous');
      await destination.rename(backup.path);
    }
    try {
      await part.rename(destination.path);
    } catch (_) {
      if (backup != null && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
    await _deleteIgnoringErrors(backup);
  }

  static Future<void> _closeIgnoringErrors(IOSink? sink) async {
    try {
      await sink?.close();
    } on Object {
      // Preserve the transfer outcome.
    }
  }

  static Future<void> _deleteIgnoringErrors(File? file) async {
    try {
      if (file != null && await file.exists()) await file.delete();
    } on Object {
      // Best-effort cleanup of an internal temporary file.
    }
  }
}
