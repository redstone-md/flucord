import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/chat_models.dart';

final class DiscordMultipartBody {
  const DiscordMultipartBody({required this.bytes, required this.contentType});

  final List<int> bytes;
  final String contentType;

  static Future<DiscordMultipartBody> build(
    Map<String, Object?> payload,
    List<PendingAttachment> attachments,
  ) async {
    final boundary =
        '----flucord-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final builder = BytesBuilder(copy: false);

    void text(String value) => builder.add(utf8.encode(value));

    text('--$boundary\r\n');
    text('Content-Disposition: form-data; name="payload_json"\r\n');
    text('Content-Type: application/json\r\n\r\n');
    text(jsonEncode(payload));
    text('\r\n');

    for (var index = 0; index < attachments.length; index++) {
      final attachment = attachments[index];
      final safeName = attachment.name
          .replaceAll(RegExp(r'[\r\n"]'), '_')
          .trim();
      text('--$boundary\r\n');
      text(
        'Content-Disposition: form-data; name="files[$index]"; '
        'filename="$safeName"\r\n',
      );
      text('Content-Type: ${_contentTypeFor(safeName)}\r\n\r\n');
      builder.add(await File(attachment.path).readAsBytes());
      text('\r\n');
    }
    text('--$boundary--\r\n');
    return DiscordMultipartBody(
      bytes: builder.takeBytes(),
      contentType: 'multipart/form-data; boundary=$boundary',
    );
  }

  /// Builds a form of plain fields plus named file parts, which is the shape
  /// the sticker create route takes.
  ///
  /// Unlike [build] there is no `payload_json`: every value is its own field,
  /// because that is what a form route expects and a single JSON blob is what
  /// a message route expects.
  static Future<DiscordMultipartBody> buildForm(
    Map<String, String> fields,
    List<({String name, String filename, List<int> bytes})> files,
  ) async {
    final boundary =
        '----flucord-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final builder = BytesBuilder(copy: false);

    void text(String value) => builder.add(utf8.encode(value));

    for (final entry in fields.entries) {
      text('--$boundary\r\n');
      text('Content-Disposition: form-data; name="${entry.key}"\r\n\r\n');
      text(entry.value);
      text('\r\n');
    }
    for (final file in files) {
      final safeName = file.filename.replaceAll(RegExp(r'[\r\n"]'), '_').trim();
      text('--$boundary\r\n');
      text(
        'Content-Disposition: form-data; name="${file.name}"; '
        'filename="$safeName"\r\n',
      );
      text('Content-Type: ${_contentTypeFor(safeName)}\r\n\r\n');
      builder.add(file.bytes);
      text('\r\n');
    }
    text('--$boundary--\r\n');
    return DiscordMultipartBody(
      bytes: builder.takeBytes(),
      contentType: 'multipart/form-data; boundary=$boundary',
    );
  }

  static String _contentTypeFor(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'txt' || 'log' || 'md' => 'text/plain',
      'pdf' => 'application/pdf',
      'ogg' || 'opus' => 'audio/ogg',
      _ => 'application/octet-stream',
    };
  }
}
