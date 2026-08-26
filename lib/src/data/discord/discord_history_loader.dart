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
    final restored = beforeMessageId == null && _onRestored != null
        ? await readRestoredHistory(_cache, channelId, pageSize: pageSize)
        : null;
    if (restored != null) _onRestored!(restored);
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
      // The page already handed out is the answer; re-reading it would only
      // decode the same rows again.
      if (restored != null) {
        return ChannelHistoryPage(
          history: restored.history,
          hasMore: restored.hasMore,
        );
      }
      final cached = await _cache.readChannelHistory(
        channelId,
        limit: pageSize,
        beforeMessageId: beforeMessageId,
      );
      if (cached.messages.isEmpty) rethrow;
      return ChannelHistoryPage(
        history: cached,
        hasMore: cached.messages.length >= pageSize,
      );
    }
  }
}
