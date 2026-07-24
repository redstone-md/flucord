import 'discord_session.dart';

final class DiscordOAuthGrant {
  factory DiscordOAuthGrant({
    required String accessToken,
    required String refreshToken,
    required Iterable<String> scopes,
    required DateTime expiresAt,
  }) {
    final normalizedAccessToken = accessToken.trim();
    final normalizedRefreshToken = refreshToken.trim();
    if (normalizedAccessToken.isEmpty) {
      throw ArgumentError.value(
        accessToken,
        'accessToken',
        'Token cannot be empty',
      );
    }
    if (normalizedRefreshToken.isEmpty) {
      throw ArgumentError.value(
        refreshToken,
        'refreshToken',
        'Token cannot be empty',
      );
    }
    return DiscordOAuthGrant._(
      normalizedAccessToken,
      normalizedRefreshToken,
      Set.unmodifiable(
        scopes.map((scope) => scope.trim()).where((scope) => scope.isNotEmpty),
      ),
      expiresAt.toUtc(),
    );
  }

  const DiscordOAuthGrant._(
    this.accessToken,
    this.refreshToken,
    this.scopes,
    this.expiresAt,
  );

  final String accessToken;
  final String refreshToken;
  final Set<String> scopes;
  final DateTime expiresAt;

  bool expiresWithin(Duration duration, DateTime now) =>
      !expiresAt.isAfter(now.toUtc().add(duration));

  DiscordOAuthUserSession get session => DiscordOAuthUserSession(
    accessToken: accessToken,
    scopes: scopes,
    expiresAt: expiresAt,
  );

  @override
  String toString() =>
      'DiscordOAuthGrant(scopes: $scopes, expiresAt: $expiresAt, tokens: <redacted>)';
}

final class DiscordOAuthAccount {
  const DiscordOAuthAccount({
    required this.id,
    required this.username,
    required this.displayName,
    required this.guildCount,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String displayName;
  final int guildCount;
  final String? avatarUrl;
}

abstract interface class DiscordOAuthGrantVault {
  Future<DiscordOAuthGrant?> read();

  Future<void> write(DiscordOAuthGrant grant);

  Future<void> clear();
}

abstract interface class DiscordOAuthAccountGateway {
  bool get isConfigured;

  Future<DiscordOAuthAccount?> restore();

  Future<DiscordOAuthAccount> authorize();

  Future<bool> handleRedirect(Uri uri);

  Future<void> clear();

  void dispose();
}

final class DiscordOAuthException implements Exception {
  const DiscordOAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
