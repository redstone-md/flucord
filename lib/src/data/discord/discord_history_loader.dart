import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import 'discord_api_client.dart';
import 'discord_mapper.dart';
import 'discord_restored_history.dart';

final class DiscordHistoryLoader {
  const DiscordHistoryLoader(
    this._api,
    this._mapper,
    this._cache, [
    this._currentMemberId,
    this._onRestored,
  ]);

  static const pageSize = 100;

  final DiscordApiClient _api;
  final DiscordMapper _mapper;
  final ChatCache _cache;
  final String? Function()? _currentMemberId;

  /// Told about the held page as soon as it is read. A host that leaves this
  /// out keeps the old behaviour, where the cache is only a fallback.
  final void Function(ChannelHistoryRestoredEvent event)? _onRestored;

  Future<ChannelHistoryPage> load(
    String channelId, {
    String? beforeMessageId,
  }) async {
    if (_onRestored case final onRestored? when beforeMessageId == null) {
      final restored = await readRestoredHistory(
        _cache,
        channelId,
        pageSize: pageSize,
      );
      if (restored != null) onRestored(restored);
    }
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
