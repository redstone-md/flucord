import 'dart:convert';

import '../domain/chat_models.dart';
import 'message_attachment_codec.dart';
import 'message_embed_codec.dart';
import 'message_sticker_codec.dart';

abstract final class MessageSnapshotCodec {
  static String encode(List<MessageSnapshot> snapshots) => jsonEncode([
    for (final snapshot in snapshots)
      {
        'type': snapshot.type.discordValue,
        'content': snapshot.body,
        'timestamp': snapshot.sentAt.toUtc().toIso8601String(),
        'edited_timestamp': snapshot.editedAt?.toUtc().toIso8601String(),
        'flags': snapshot.flags,
        'attachments_json': MessageAttachmentCodec.encode(snapshot.attachments),
        'embeds_json': MessageEmbedCodec.encode(snapshot.embeds),
        'stickers_json': MessageStickerCodec.encode(snapshot.stickers),
        'mention_user_ids': snapshot.mentionedUserIds.toList(),
        'mention_role_ids': snapshot.mentionedRoleIds.toList(),
        'components': [
          for (final component in snapshot.components) component.payloadJson,
        ],
      },
  ]);

  static List<MessageSnapshot> decode(String source) {
    final value = jsonDecode(source);
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((raw) => raw.cast<String, Object?>())
        .map(_fromMap)
        .toList(growable: false);
  }

  static MessageSnapshot _fromMap(Map<String, Object?> raw) => MessageSnapshot(
    type: DiscordMessageType.fromDiscordValue(raw['type'] as int?),
    body: raw['content'] as String? ?? '',
    sentAt: DateTime.parse(raw['timestamp']! as String).toLocal(),
    editedAt: switch (raw['edited_timestamp']) {
      final String value => DateTime.tryParse(value)?.toLocal(),
      _ => null,
    },
    flags: raw['flags'] as int? ?? 0,
    attachments: MessageAttachmentCodec.decode(
      raw['attachments_json'] as String? ?? '[]',
    ),
    embeds: MessageEmbedCodec.decode(raw['embeds_json'] as String? ?? '[]'),
    stickers: MessageStickerCodec.decode(
      raw['stickers_json'] as String? ?? '[]',
    ),
    mentionedUserIds: (raw['mention_user_ids'] as List? ?? const [])
        .whereType<String>()
        .toSet(),
    mentionedRoleIds: (raw['mention_role_ids'] as List? ?? const [])
        .whereType<String>()
        .toSet(),
    components: (raw['components'] as List? ?? const [])
        .whereType<String>()
        .map(MessageComponentSnapshot.new)
        .toList(growable: false),
  );
}
