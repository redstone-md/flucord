part of 'chat_models.dart';

final class GuildSticker {
  GuildSticker({
    required this.item,
    required this.spaceId,
    required List<String> tags,
    required this.available,
    this.description,
  }) : tags = List.unmodifiable(tags);

  final MessageSticker item;
  final String spaceId;
  final String? description;
  final List<String> tags;
  final bool available;

  String get id => item.id;
  String get name => item.name;
}

extension GuildStickerWorkspace on ChatWorkspace {
  List<GuildSticker> stickersFor(String spaceId) => stickers
      .where((sticker) => sticker.spaceId == spaceId && sticker.available)
      .toList(growable: false);

  ChatWorkspace replaceGuildStickers(
    String spaceId,
    List<GuildSticker> replacements,
  ) => copyWith(
    stickers: [
      ...stickers.where((sticker) => sticker.spaceId != spaceId),
      ...replacements,
    ],
  );
}
