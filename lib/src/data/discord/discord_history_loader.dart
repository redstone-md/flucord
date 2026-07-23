import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import 'discord_api_client.dart';
import 'discord_mapper.dart';

final class DiscordHistoryLoader {
  const DiscordHistoryLoader(
    this._api,
    this._mapper,
    this._cache, [
    this._currentMemberId,
  ]);

  static const pageSize = 100;

  final DiscordApiClient _api;
  final DiscordMapper _mapper;
  final ChatCache _cache;
  final String? Function()? _currentMemberId;

  Future<ChannelHistoryPage> load(
    String channelId, {
    String? beforeMessageId,
  }) async {
    try {
      final payloads = await _api.getChannelMessages(
        channelId,
        limit: pageSize,
        beforeMessageId: beforeMessageId,
      );
      final history = _mapper.history(
        channelId,
        payloads,
        currentMemberId: _currentMemberId?.call(),
      );
      await _cache.writeChannelHistory(history, replaceExisting: false);
      return ChannelHistoryPage(
        history: history,
        hasMore: payloads.length == pageSize,
      );
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      final cached = _cachedPage(
        await _cache.readChannelHistory(channelId),
        beforeMessageId,
      );
      if (cached.history.messages.isNotEmpty) return cached;
      rethrow;
    }
  }

  ChannelHistoryPage _cachedPage(
    ChannelHistory cached,
    String? beforeMessageId,
  ) {
    final messages = cached.messages;
    final end = beforeMessageId == null
        ? messages.length
        : messages.indexWhere((message) => message.id == beforeMessageId);
    if (end <= 0) {
      return ChannelHistoryPage(
        history: ChannelHistory(
          channelId: cached.channelId,
          messages: const [],
          members: cached.members,
        ),
        hasMore: false,
      );
    }
    final start = end > pageSize ? end - pageSize : 0;
    return ChannelHistoryPage(
      history: ChannelHistory(
        channelId: cached.channelId,
        messages: messages.sublist(start, end),
        members: cached.members,
      ),
      hasMore: start > 0,
    );
  }
}
