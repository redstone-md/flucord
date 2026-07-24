enum DiscordSocialSdkAvailabilityStatus {
  ready,
  sdkNotBundled,
  unsupportedPlatform,
  failure,
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
}
