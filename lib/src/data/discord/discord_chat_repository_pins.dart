part of 'discord_chat_repository.dart';

extension _DiscordChatRepositoryPins on DiscordChatRepository {
  Future<ChannelHistory> _loadPinnedMessages(String channelId) =>
      readPinsThroughCache(
        _cache,
        channelId,
        () async => _mapper.history(
          channelId,
          await _api.getChannelPins(channelId),
          currentMemberId: _currentMemberId,
        ),
      );
}
