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

final class DiscordOAuthGuildMembership {
  factory DiscordOAuthGuildMembership({
    required String guildId,
    String? nickname,
    String? avatarUrl,
    Iterable<String> roleIds = const [],
    DateTime? joinedAt,
    DateTime? premiumSince,
    bool pending = false,
    DateTime? communicationDisabledUntil,
  }) {
    final normalizedGuildId = guildId.trim();
    if (normalizedGuildId.isEmpty) {
      throw ArgumentError.value(guildId, 'guildId', 'Cannot be empty');
    }
    final normalizedNickname = nickname?.trim();
    return DiscordOAuthGuildMembership._(
      guildId: normalizedGuildId,
      nickname: normalizedNickname == null || normalizedNickname.isEmpty
          ? null
          : normalizedNickname,
      avatarUrl: avatarUrl,
      roleIds: List.unmodifiable(
        roleIds
            .map((roleId) => roleId.trim())
            .where((roleId) => roleId.isNotEmpty),
      ),
      joinedAt: joinedAt?.toUtc(),
      premiumSince: premiumSince?.toUtc(),
      pending: pending,
      communicationDisabledUntil: communicationDisabledUntil?.toUtc(),
    );
  }

  const DiscordOAuthGuildMembership._({
    required this.guildId,
    required this.nickname,
    required this.avatarUrl,
    required this.roleIds,
    required this.joinedAt,
    required this.premiumSince,
    required this.pending,
    required this.communicationDisabledUntil,
  });

  final String guildId;
  final String? nickname;
  final String? avatarUrl;
  final List<String> roleIds;
  final DateTime? joinedAt;
  final DateTime? premiumSince;
  final bool pending;
  final DateTime? communicationDisabledUntil;

  int get roleCount => roleIds.length;
}

final class DiscordOAuthConnection {
  factory DiscordOAuthConnection({
    required String id,
    required String name,
    required String type,
    bool revoked = false,
    bool verified = false,
    bool friendSync = false,
    bool showActivity = false,
    bool twoWayLink = false,
    int visibility = 0,
  }) {
    final normalizedId = id.trim();
    final normalizedName = name.trim();
    final normalizedType = type.trim().toLowerCase();
    if (normalizedId.isEmpty ||
        normalizedName.isEmpty ||
        normalizedType.isEmpty) {
      throw ArgumentError('Connection id, name, and type cannot be empty');
    }
    return DiscordOAuthConnection._(
      id: normalizedId,
      name: normalizedName,
      type: normalizedType,
      revoked: revoked,
      verified: verified,
      friendSync: friendSync,
      showActivity: showActivity,
      twoWayLink: twoWayLink,
      visibility: visibility,
    );
  }

  const DiscordOAuthConnection._({
    required this.id,
    required this.name,
    required this.type,
    required this.revoked,
    required this.verified,
    required this.friendSync,
    required this.showActivity,
    required this.twoWayLink,
    required this.visibility,
  });

  final String id;
  final String name;
  final String type;
  final bool revoked;
  final bool verified;
  final bool friendSync;
  final bool showActivity;
  final bool twoWayLink;
  final int visibility;

  bool get isPublic => visibility == 1;
}

final class DiscordOAuthAccount {
  factory DiscordOAuthAccount({
    required String id,
    required String username,
    required String displayName,
    String? discriminator,
    String? avatarUrl,
    String? bannerUrl,
    int? accentColor,
    String? locale,
    bool isVerified = false,
    bool mfaEnabled = false,
    int publicFlags = 0,
    Iterable<DiscordOAuthGuild> guilds = const [],
    Iterable<DiscordOAuthConnection> connections = const [],
  }) => DiscordOAuthAccount._(
    id: id,
    username: username,
    displayName: displayName,
    discriminator: _optionalText(discriminator),
    avatarUrl: avatarUrl,
    bannerUrl: bannerUrl,
    accentColor:
        accentColor != null && accentColor >= 0 && accentColor <= 0xFFFFFF
        ? accentColor
        : null,
    locale: _optionalText(locale),
    isVerified: isVerified,
    mfaEnabled: mfaEnabled,
    publicFlags: publicFlags < 0 ? 0 : publicFlags,
    guilds: List.unmodifiable(guilds),
    connections: List.unmodifiable(connections),
  );

  const DiscordOAuthAccount._({
    required this.id,
    required this.username,
    required this.displayName,
    required this.discriminator,
    required this.avatarUrl,
    required this.bannerUrl,
    required this.accentColor,
    required this.locale,
    required this.isVerified,
    required this.mfaEnabled,
    required this.publicFlags,
    required this.guilds,
    required this.connections,
  });

  final String id;
  final String username;
  final String displayName;
  final String? discriminator;
  final String? avatarUrl;
  final String? bannerUrl;
  final int? accentColor;
  final String? locale;
  final bool isVerified;
  final bool mfaEnabled;
  final int publicFlags;
  final List<DiscordOAuthGuild> guilds;
  final List<DiscordOAuthConnection> connections;

  int get guildCount => guilds.length;
  int get connectionCount => connections.length;

  String get usernameLabel => discriminator != null && discriminator != '0'
      ? '$username#$discriminator'
      : '@$username';

  static String? _optionalText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
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

  Future<DiscordOAuthGuildMembership> fetchCurrentGuildMembership(
    String guildId,
  );

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
