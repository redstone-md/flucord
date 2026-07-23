part of 'discord_mapper.dart';

extension DiscordStickerMapper on DiscordMapper {
  GuildSticker guildSticker(Map<String, Object?> payload, String guildId) {
    final id = payload['id']! as String;
    final name = payload['name']! as String;
    final format = StickerFormat.fromDiscordValue(
      payload['format_type'] as int?,
    );
    final tags = (payload['tags'] as String? ?? '')
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    return GuildSticker(
      item: MessageSticker(
        id: id,
        name: name,
        format: format,
        url: DiscordCdn.sticker(id, format),
      ),
      spaceId: guildId,
      description: payload['description'] as String?,
      tags: tags,
      available: payload['available'] as bool? ?? true,
    );
  }

  List<MessageSticker> _mapStickerItems(Object? value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((raw) => raw.cast<String, Object?>())
          .map(_mapStickerItem)
          .whereType<MessageSticker>()
          .toList(growable: false);

  MessageSticker? _mapStickerItem(Map<String, Object?> payload) {
    final id = payload['id'] as String?;
    final name = payload['name'] as String?;
    if (id == null || name == null) return null;
    final format = StickerFormat.fromDiscordValue(
      payload['format_type'] as int?,
    );
    return MessageSticker(
      id: id,
      name: name,
      format: format,
      url: DiscordCdn.sticker(id, format),
    );
  }
}
