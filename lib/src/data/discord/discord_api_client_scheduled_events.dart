part of 'discord_api_client.dart';

extension DiscordScheduledEventApi on DiscordApiClient {
  Future<List<Map<String, Object?>>> getGuildScheduledEvents(String guildId) =>
      _getList(
        '/guilds/$guildId/scheduled-events',
        query: const {'with_user_count': 'true'},
      );
}
