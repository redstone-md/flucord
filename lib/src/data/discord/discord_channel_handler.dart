import '../../domain/chat_cache.dart';
import '../../domain/chat_repository.dart';
import 'discord_mapper.dart';

/// Applies a channel, thread or category dispatch.
///
/// Each method announces before it writes. The announcement happens before the
/// first `await`, so it goes out in dispatch order: a message that arrives right
/// behind its new channel finds the channel already in the workspace. Announcing
/// after the write let the message overtake the channel, and its unread marker
/// was lost.
final class DiscordChannelHandler {
  const DiscordChannelHandler(this._cache, this._mapper, this._publish);

  final ChatCache _cache;
  final DiscordMapper _mapper;
  final void Function(ChatRepositoryEvent event) _publish;

  Future<void> upsert(Map<String, Object?> payload, String guildId) async {
    final category = _mapper.category(payload, guildId);
    if (category != null) {
      _publish(CategoryUpsertedEvent(category));
      await _cache.writeCategory(category);
      return;
    }
    final channel = _mapper.channel(payload, guildId);
    if (channel == null) return;
    _publish(ChannelUpsertedEvent(channel));
    await _cache.writeChannel(channel);
  }

  Future<void> delete(Map<String, Object?> payload) async {
    final id = payload['id'] as String?;
    if (id == null) return;
    if (payload['type'] == 4) {
      _publish(CategoryDeletedEvent(id));
      await _cache.deleteCategory(id);
      return;
    }
    _publish(ChannelDeletedEvent(id));
    await _cache.deleteChannel(id);
  }
}
