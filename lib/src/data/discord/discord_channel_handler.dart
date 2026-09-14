import '../../domain/chat_cache.dart';
import '../../domain/chat_repository.dart';
import 'discord_mapper.dart';

final class DiscordChannelHandler {
  const DiscordChannelHandler(this._cache, this._mapper);

  final ChatCache _cache;
  final DiscordMapper _mapper;

  Future<ChatRepositoryEvent?> upsert(
    Map<String, Object?> payload,
    String guildId,
  ) async {
    final category = _mapper.category(payload, guildId);
    if (category != null) {
      await _cache.writeCategory(category);
      return CategoryUpsertedEvent(category);
    }
    final channel = _mapper.channel(payload, guildId);
    if (channel == null) return null;
    await _cache.writeChannel(channel);
    return ChannelUpsertedEvent(channel);
  }

  Future<ChatRepositoryEvent?> delete(Map<String, Object?> payload) async {
    final id = payload['id'] as String?;
    if (id == null) return null;
    if (payload['type'] == 4) {
      await _cache.deleteCategory(id);
      return CategoryDeletedEvent(id);
    }
    await _cache.deleteChannel(id);
    return ChannelDeletedEvent(id);
  }
}
