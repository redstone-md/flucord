import 'dart:convert';

import '../domain/chat_models.dart';

abstract final class MessageStickerCodec {
  static String encode(List<MessageSticker> stickers) => jsonEncode([
    for (final sticker in stickers)
      {
        'id': sticker.id,
        'name': sticker.name,
        'format_type': sticker.format.discordValue,
        'url': sticker.url,
      },
  ]);

  static List<MessageSticker> decode(String source) {
    final value = jsonDecode(source);
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(_fromMap)
        .whereType<MessageSticker>()
        .toList(growable: false);
  }

  static MessageSticker? _fromMap(Map<dynamic, dynamic> raw) {
    final id = raw['id'] as String?;
    final name = raw['name'] as String?;
    final url = raw['url'] as String?;
    if (id == null || name == null || url == null) return null;
    return MessageSticker(
      id: id,
      name: name,
      format: StickerFormat.fromDiscordValue(raw['format_type'] as int?),
      url: url,
    );
  }
}
