import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import 'discord_rest_client.dart';

/// Reads [channelId]'s pins with [fetch], the same on the bot and desktop
/// transports. What Discord answers is kept, the people with it, so the pins
/// show their authors offline too. A failed read falls back to the cached
/// pins, except a refused session: that has to reach the caller, which signs
/// out.
Future<ChannelHistory> readPinsThroughCache(
  ChatCache cache,
  String channelId,
  Future<ChannelHistory> Function() fetch,
) async {
  try {
    final history = await fetch();
    for (final member in history.members) {
      await cache.writeMember(member);
    }
    for (final message in history.messages) {
      await cache.writeMessage(message);
    }
    return history;
  } catch (error) {
    if (error is DiscordApiException && error.isUnauthorized) rethrow;
    final cached = await cache.readPinnedMessages(channelId);
    if (cached.messages.isNotEmpty) return cached;
    rethrow;
  }
}
