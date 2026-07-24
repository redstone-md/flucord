import 'dart:convert';

import '../domain/chat_models.dart';

abstract final class MessageAttachmentCodec {
  static String encode(List<MessageAttachment> attachments) =>
      jsonEncode(attachments.map(toMap).toList(growable: false));

  static List<MessageAttachment> decode(String source) =>
      listFrom(jsonDecode(source));

  static List<MessageAttachment> listFrom(Object? value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((raw) => fromMap(raw.cast<String, Object?>()))
          .toList(growable: false);

  static MessageAttachment fromMap(Map<String, Object?> raw) =>
      MessageAttachment(
        id: raw['id'] as String? ?? '',
        fileName: raw['filename'] as String? ?? 'attachment',
        url: raw['url'] as String? ?? '',
        size: raw['size'] as int? ?? 0,
        contentType: raw['content_type'] as String?,
        width: raw['width'] as int?,
        height: raw['height'] as int?,
        durationSecs: (raw['duration_secs'] as num?)?.toDouble(),
        waveform: raw['waveform'] as String?,
      );

  static Map<String, Object?> toMap(MessageAttachment attachment) => {
    'id': attachment.id,
    'filename': attachment.fileName,
    'url': attachment.url,
    'size': attachment.size,
    'content_type': attachment.contentType,
    'width': attachment.width,
    'height': attachment.height,
    'duration_secs': attachment.durationSecs,
    'waveform': attachment.waveform,
  };
}
