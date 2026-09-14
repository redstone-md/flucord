import 'discord_api_client.dart';

final class DiscordGuildMemberLoader {
  const DiscordGuildMemberLoader(this._api);

  final DiscordApiClient _api;

  Future<List<Map<String, Object?>>> load(String guildId) async {
    try {
      return await _api.getGuildMembers(guildId);
    } on DiscordApiException catch (error) {
      if (error.isForbidden) return const [];
      rethrow;
    }
  }
}
