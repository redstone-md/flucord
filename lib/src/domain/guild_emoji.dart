part of 'chat_models.dart';

final class GuildEmoji {
  const GuildEmoji({
    required this.id,
    required this.spaceId,
    required this.name,
    this.imageUrl,
    this.animated = false,
    this.available = true,
  });

  final String id;
  final String spaceId;
  final String name;
  final String? imageUrl;
  final bool animated;
  final bool available;

  String get messageSyntax => '<${animated ? 'a' : ''}:$name:$id>';
  String get reactionKey => '$name:$id';
}

extension GuildEmojiWorkspace on ChatWorkspace {
  List<GuildEmoji> emojisFor(String spaceId) => emojis
      .where((emoji) => emoji.spaceId == spaceId && emoji.available)
      .toList(growable: false);

  ChatWorkspace replaceGuildEmojis(
    String spaceId,
    List<GuildEmoji> replacements,
  ) => copyWith(
    emojis: [
      ...emojis.where((emoji) => emoji.spaceId != spaceId),
      ...replacements,
    ],
  );
}
