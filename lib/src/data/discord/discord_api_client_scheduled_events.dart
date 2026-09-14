part of 'discord_api_client.dart';

extension DiscordScheduledEventApi on DiscordApiClient {
  /// `PUT`/`DELETE /guilds/{id}/scheduled-events/{event}[/{exception}]/users/@me`.
  ///
  /// The response value is Discord's own: 1 for interested. Taking it back
  /// sends no body at all, which is how Discord distinguishes the two.
  Future<void> setGuildScheduledEventInterest({
    required String guildId,
    required String eventId,
    required bool interested,
    String? exceptionId,
  }) {
    final occurrence = exceptionId == null || exceptionId.isEmpty
        ? ''
        : '/$exceptionId';
    final path =
        '/guilds/$guildId/scheduled-events/$eventId$occurrence/users/@me';
    return interested
        ? _rest.requestEmpty('PUT', path, body: const {'response': 1})
        : _rest.requestEmpty('DELETE', path);
  }

  Future<List<Map<String, Object?>>> getGuildScheduledEvents(String guildId) =>
      _getList(
        '/guilds/$guildId/scheduled-events',
        query: const {'with_user_count': 'true'},
      );
}
