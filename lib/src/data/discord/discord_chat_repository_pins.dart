part of 'discord_chat_repository.dart';

extension _DiscordChatRepositoryPins on DiscordChatRepository {
  Future<ChannelHistory> _loadPinnedMessages(String channelId) async {
    try {
      final history = _mapper.history(
        channelId,
        await _api.getChannelPins(channelId),
        currentMemberId: _currentMemberId,
      );
      for (final member in history.members) {
        await _cache.writeMember(member);
      }
      for (final message in history.messages) {
        await _cache.writeMessage(message);
      }
      return history;
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      final cached = await _cache.readPinnedMessages(channelId);
      if (cached.messages.isNotEmpty) return cached;
      rethrow;
    }
  }
}
