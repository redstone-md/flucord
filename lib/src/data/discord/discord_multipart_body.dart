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

  static String _contentTypeFor(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'txt' || 'log' || 'md' => 'text/plain',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
  }
}
