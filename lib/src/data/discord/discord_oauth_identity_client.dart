import '../../domain/discord_session.dart';
import 'discord_rest_client.dart';

final class DiscordOAuthCapabilityException implements Exception {
  const DiscordOAuthCapabilityException(this.capability);

  final DiscordSessionCapability capability;

  @override
  String toString() =>
      'Discord OAuth session lacks ${capability.name} capability';
}

final class DiscordOAuthSessionExpiredException implements Exception {
  const DiscordOAuthSessionExpiredException();

  @override
  String toString() => 'Discord OAuth session has expired';
}

final class DiscordOAuthIdentityClient {
  DiscordOAuthIdentityClient({
    required DiscordOAuthUserSession session,
    DiscordHttpTransport? transport,
    DelayFunction? delay,
    Uri? baseUri,
  }) : _session = session,
       _rest = DiscordRestClient(
         authorization: DiscordBearerAuthorization(session.transportCredential),
         transport: transport,
         delay: delay,
         baseUri: baseUri,
       );

  final DiscordOAuthUserSession _session;
  final DiscordRestClient _rest;

  Future<Map<String, Object?>> getCurrentUser() async {
    _require(DiscordSessionCapability.currentIdentity);
    return _rest.getObject('/users/@me');
  }

  Future<List<Map<String, Object?>>> getCurrentUserGuilds() async {
    _require(DiscordSessionCapability.guildDirectory);
    final guilds = <Map<String, Object?>>[];
    String? after;
    do {
      final query = <String, String>{'limit': '200', 'with_counts': 'true'};
      if (after != null) query['after'] = after;
      final page = await _rest.getList('/users/@me/guilds', query: query);
      guilds.addAll(page);
      after = page.length == 200 ? page.last['id'] as String? : null;
    } while (after != null);
    return guilds;
  }

  void _require(DiscordSessionCapability capability) {
    if (_session.isExpired) {
      throw const DiscordOAuthSessionExpiredException();
    }
    if (!_session.supports(capability)) {
      throw DiscordOAuthCapabilityException(capability);
    }
  }

  void close() => _rest.close();

  @override
  String toString() => 'DiscordOAuthIdentityClient(<redacted>)';
}
