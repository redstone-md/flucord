part of 'discord_chat_repository.dart';

extension _DiscordChatRepositoryEmojis on DiscordChatRepository {
  Future<void> _handleGuildEmojis(Map<String, Object?> data) async {
    final guildId = (data['guild_id'] ?? data['id']) as String?;
    final rawEmojis = data['emojis'];
    if (guildId == null || rawEmojis is! List) return;
    final emojis = rawEmojis
        .whereType<Map>()
        .map(
          (payload) => _mapper.emoji(payload.cast<String, Object?>(), guildId),
        )
        .toList(growable: false);
    await _cache.replaceGuildEmojis(guildId, emojis);
    if (_events.isClosed) return;
    _events.add(GuildEmojisReplacedEvent(spaceId: guildId, emojis: emojis));
  }
}
