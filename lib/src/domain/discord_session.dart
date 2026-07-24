enum DiscordSessionKind { botApplication, oauthUser }

enum DiscordSessionCapability {
  currentIdentity,
  guildDirectory,
  directChannelDirectory,
  channelMessages,
  realtimeGateway,
  directMessages,
  voiceConnection,
}

sealed class DiscordAccountSession {
  const DiscordAccountSession();

  DiscordSessionKind get kind;
  Set<DiscordSessionCapability> get capabilities;
  String get displayName;
  String get credentialLabel;
  String get transportCredential;

  bool supports(DiscordSessionCapability capability) =>
      capabilities.contains(capability);
}

final class DiscordBotSession extends DiscordAccountSession {
  factory DiscordBotSession(String token) {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token cannot be empty');
    }
    return DiscordBotSession._(normalized);
  }

  const DiscordBotSession._(this._token);

  static const _capabilities = <DiscordSessionCapability>{
    DiscordSessionCapability.currentIdentity,
    DiscordSessionCapability.guildDirectory,
    DiscordSessionCapability.channelMessages,
    DiscordSessionCapability.realtimeGateway,
    DiscordSessionCapability.directMessages,
    DiscordSessionCapability.voiceConnection,
  };

  final String _token;

  @override
  DiscordSessionKind get kind => DiscordSessionKind.botApplication;

  @override
  Set<DiscordSessionCapability> get capabilities => _capabilities;

  @override
  String get displayName => 'Discord bot';

  @override
  String get credentialLabel => 'bot token';

  @override
  String get transportCredential => _token;

  @override
  String toString() => 'DiscordBotSession(<redacted>)';
}

final class DiscordOAuthUserSession extends DiscordAccountSession {
  factory DiscordOAuthUserSession({
    required String accessToken,
    required Iterable<String> scopes,
    required DateTime expiresAt,
  }) {
    final normalized = accessToken.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        accessToken,
        'accessToken',
        'Token cannot be empty',
      );
    }
    return DiscordOAuthUserSession._(
      normalized,
      Set.unmodifiable(
        scopes.map((scope) => scope.trim()).where((scope) => scope.isNotEmpty),
      ),
      expiresAt.toUtc(),
    );
  }

  const DiscordOAuthUserSession._(
    this._accessToken,
    this.scopes,
    this.expiresAt,
  );

  final String _accessToken;
  final Set<String> scopes;
  final DateTime expiresAt;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());

  @override
  DiscordSessionKind get kind => DiscordSessionKind.oauthUser;

  @override
  Set<DiscordSessionCapability> get capabilities => Set.unmodifiable({
    if (scopes.contains('identify') || scopes.contains('email'))
      DiscordSessionCapability.currentIdentity,
    if (scopes.contains('guilds')) DiscordSessionCapability.guildDirectory,
    if (scopes.contains('dm_channels.read'))
      DiscordSessionCapability.directChannelDirectory,
    if (scopes.contains('voice')) DiscordSessionCapability.voiceConnection,
  });

  @override
  String get displayName => 'Discord OAuth user';

  @override
  String get credentialLabel => 'OAuth access token';

  @override
  String get transportCredential => _accessToken;

  @override
  String toString() =>
      'DiscordOAuthUserSession(scopes: $scopes, expiresAt: $expiresAt, token: <redacted>)';
}
