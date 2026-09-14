part of 'discord_api_client.dart';

extension DiscordApiClientReactions on DiscordApiClient {
  Future<List<Map<String, Object?>>> getReactions({
    required String channelId,
    required String messageId,
    required String emoji,
    required DiscordReactionType type,
    String? afterUserId,
    int limit = 100,
  }) {
    final encodedEmoji = Uri.encodeComponent(emoji);
    return _getList(
      '/channels/$channelId/messages/$messageId/reactions/$encodedEmoji',
      query: {
        'type': '${type.discordValue}',
        'limit': '${limit.clamp(1, 100)}',
        'after': ?afterUserId,
      },
    );
  }
}
