import '../../domain/chat_cache.dart';
import '../../domain/chat_repository.dart';

/// The newest held page for a channel, or null where nothing is held.
///
/// Opening a channel reads this first and puts it on screen, then asks Discord
/// for the same page. Both transports do it, so the read and the "is there
/// more behind this" answer live here rather than being written twice.
Future<ChannelHistoryRestoredEvent?> readRestoredHistory(
  ChatCache cache,
  String channelId, {
  required int pageSize,
}) async {
  final history = await cache.readChannelHistory(channelId, limit: pageSize);
  if (history.messages.isEmpty) return null;
  // A full page read back means the channel most likely holds more behind it.
  // Being wrong here costs one empty request for older messages.
  return ChannelHistoryRestoredEvent(
    history: history,
    hasMore: history.messages.length >= pageSize,
  );
}
