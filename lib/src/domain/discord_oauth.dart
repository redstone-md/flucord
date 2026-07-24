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

final class DiscordOAuthGuild {
  factory DiscordOAuthGuild({
    required String id,
    required String name,
    String? iconUrl,
    String? bannerUrl,
    bool isOwner = false,
    String permissions = '0',
    Iterable<String> features = const [],
    int? approximateMemberCount,
    int? approximatePresenceCount,
  }) => DiscordOAuthGuild._(
    id: id,
    name: name,
    iconUrl: iconUrl,
    bannerUrl: bannerUrl,
    isOwner: isOwner,
    permissions: permissions,
    features: Set.unmodifiable(features),
    approximateMemberCount: approximateMemberCount,
    approximatePresenceCount: approximatePresenceCount,
  );

  const DiscordOAuthGuild._({
    required this.id,
    required this.name,
    required this.iconUrl,
    required this.bannerUrl,
    required this.isOwner,
    required this.permissions,
    required this.features,
    required this.approximateMemberCount,
    required this.approximatePresenceCount,
  });

  final String id;
  final String name;
  final String? iconUrl;
  final String? bannerUrl;
  final bool isOwner;
  final String permissions;
  final Set<String> features;
  final int? approximateMemberCount;
  final int? approximatePresenceCount;

  bool get isAdministrator {
    final value = BigInt.tryParse(permissions);
    return value != null && (value & BigInt.from(8)) != BigInt.zero;
  }
}

final class DiscordOAuthAccount {
  factory DiscordOAuthAccount({
    required String id,
    required String username,
    required String displayName,
    String? avatarUrl,
    Iterable<DiscordOAuthGuild> guilds = const [],
  }) => DiscordOAuthAccount._(
    id: id,
    username: username,
    displayName: displayName,
    avatarUrl: avatarUrl,
    guilds: List.unmodifiable(guilds),
  );

  const DiscordOAuthAccount._({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.guilds,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final List<DiscordOAuthGuild> guilds;

  int get guildCount => guilds.length;
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
