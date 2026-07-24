part of 'discord_mapper.dart';

extension _DiscordMessageSnapshotMapper on DiscordMapper {
  List<MessageSnapshot> _mapMessageSnapshots(Object? value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((raw) => raw['message'])
          .whereType<Map>()
          .map((raw) => raw.cast<String, Object?>())
          .map(_mapMessageSnapshot)
          .toList(growable: false);

  MessageSnapshot _mapMessageSnapshot(Map<String, Object?> payload) {
    final rawTimestamp = payload['timestamp'] as String?;
    final rawEditedAt = payload['edited_timestamp'] as String?;
    final stickerValue = payload.containsKey('sticker_items')
        ? payload['sticker_items']
        : payload['stickers'];
    return MessageSnapshot(
      type: DiscordMessageType.fromDiscordValue(payload['type'] as int?),
      body: payload['content'] as String? ?? '',
      sentAt:
          DateTime.tryParse(rawTimestamp ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      editedAt: DateTime.tryParse(rawEditedAt ?? '')?.toLocal(),
      flags: payload['flags'] as int? ?? 0,
      attachments: MessageAttachmentCodec.listFrom(payload['attachments']),
      embeds: MessageEmbedCodec.listFrom(payload['embeds']),
      stickers: _mapStickerItems(stickerValue),
      mentionedUserIds: (payload['mentions'] as List? ?? const [])
          .whereType<Map>()
          .map((mention) => mention['id'])
          .whereType<String>()
          .toSet(),
      mentionedRoleIds: (payload['mention_roles'] as List? ?? const [])
          .whereType<String>()
          .toSet(),
      components: (payload['components'] as List? ?? const [])
          .whereType<Map>()
          .map((component) => jsonEncode(component))
          .map(MessageComponentSnapshot.new)
          .toList(growable: false),
    );
  }
}
