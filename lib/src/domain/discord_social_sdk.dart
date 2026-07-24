import 'discord_relationship.dart';

enum DiscordSocialSdkAvailabilityStatus {
  ready,
  sdkNotBundled,
  unsupportedPlatform,
  failure,
}

enum DiscordSocialSdkAuthenticationStatus { ready, signedOut, unconfigured }

final class DiscordSocialSdkAuthentication {
  const DiscordSocialSdkAuthentication._(this.status);

  static const ready = DiscordSocialSdkAuthentication._(
    DiscordSocialSdkAuthenticationStatus.ready,
  );
  static const signedOut = DiscordSocialSdkAuthentication._(
    DiscordSocialSdkAuthenticationStatus.signedOut,
  );
  static const unconfigured = DiscordSocialSdkAuthentication._(
    DiscordSocialSdkAuthenticationStatus.unconfigured,
  );

  final DiscordSocialSdkAuthenticationStatus status;

  bool get isReady => status == DiscordSocialSdkAuthenticationStatus.ready;
}

final class DiscordSocialSdkGrant {
  factory DiscordSocialSdkGrant({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
    required Iterable<String> scopes,
  }) {
    final normalizedAccessToken = accessToken.trim();
    final normalizedRefreshToken = refreshToken.trim();
    if (normalizedAccessToken.isEmpty || normalizedRefreshToken.isEmpty) {
      throw ArgumentError('Social SDK tokens must not be empty.');
    }
    return DiscordSocialSdkGrant._(
      accessToken: normalizedAccessToken,
      refreshToken: normalizedRefreshToken,
      expiresAt: expiresAt.toUtc(),
      scopes: Set.unmodifiable(
        scopes.map((scope) => scope.trim()).where((scope) => scope.isNotEmpty),
      ),
    );
  }

  const DiscordSocialSdkGrant._({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.scopes,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final Set<String> scopes;

  @override
  String toString() => 'DiscordSocialSdkGrant(<redacted>)';
}

abstract interface class DiscordSocialSdkGrantVault {
  Future<DiscordSocialSdkGrant?> read();

  Future<void> write(DiscordSocialSdkGrant grant);

  Future<void> clear();
}

abstract interface class DiscordSocialSdkAuthenticationEvents {
  Stream<DiscordSocialSdkAuthentication> get authenticationChanges;
}

final class DiscordSocialSdkAvailability {
  const DiscordSocialSdkAvailability._({
    required this.status,
    required this.diagnosticCode,
  });

  static const ready = DiscordSocialSdkAvailability._(
    status: DiscordSocialSdkAvailabilityStatus.ready,
    diagnosticCode: 'ready',
  );

  static const sdkNotBundled = DiscordSocialSdkAvailability._(
    status: DiscordSocialSdkAvailabilityStatus.sdkNotBundled,
    diagnosticCode: 'sdk_not_bundled',
  );

  static const unsupportedPlatform = DiscordSocialSdkAvailability._(
    status: DiscordSocialSdkAvailabilityStatus.unsupportedPlatform,
    diagnosticCode: 'unsupported_platform',
  );

  factory DiscordSocialSdkAvailability.failure(String diagnosticCode) =>
      DiscordSocialSdkAvailability._(
        status: DiscordSocialSdkAvailabilityStatus.failure,
        diagnosticCode: diagnosticCode.trim().isEmpty
            ? 'unknown_failure'
            : diagnosticCode.trim(),
      );

  final DiscordSocialSdkAvailabilityStatus status;
  final String diagnosticCode;

  bool get isReady => status == DiscordSocialSdkAvailabilityStatus.ready;
}

abstract interface class DiscordSocialSdkGateway {
  Future<DiscordSocialSdkAvailability> checkAvailability();

  Future<DiscordSocialSdkAuthentication> restoreAuthentication();

  Future<DiscordSocialSdkAuthentication> authorize();

  Future<void> disconnect();

  Future<List<DiscordRelationship>> fetchRelationships();

  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  });
}
