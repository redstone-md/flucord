import 'dart:convert';

final class DiscordDesktopProtocolProfile {
  const DiscordDesktopProtocolProfile({
    required this.clientBuildNumber,
    this.apiVersion = 9,
    this.gatewayVersion = 9,
    this.gatewayCapabilities = 1734653,
    this.gatewayEncoding = 'etf',
    this.gatewayCompression = 'zstd-stream',
    this.maxGuildSubscriptionBytes = 15360,
    this.apiHost = 'discord.com',
    this.gatewayHost = 'gateway.discord.gg',
  });

  static const installedStable20260725 = DiscordDesktopProtocolProfile(
    clientBuildNumber: 582977,
  );

  final int clientBuildNumber;
  final int apiVersion;
  final int gatewayVersion;
  final int gatewayCapabilities;
  final String gatewayEncoding;
  final String gatewayCompression;
  final int maxGuildSubscriptionBytes;
  final String apiHost;
  final String gatewayHost;

  Uri get apiBaseUri => Uri.https(apiHost, '/api/v$apiVersion');

  Uri gatewayUri({Uri? resumeUri}) {
    final base = resumeUri ?? Uri(scheme: 'wss', host: gatewayHost);
    return base.replace(
      queryParameters: {
        'encoding': gatewayEncoding,
        'v': '$gatewayVersion',
        'compress': gatewayCompression,
      },
    );
  }
}

final class DiscordDesktopSuperProperties {
  DiscordDesktopSuperProperties({
    required this.os,
    required this.systemLocale,
    required this.browserUserAgent,
    required this.browserVersion,
    required this.osVersion,
    required this.releaseChannel,
    required this.clientBuildNumber,
    required this.nativeBuildNumber,
    required this.clientLaunchId,
    this.browser = 'Discord Client',
    this.device = '',
    this.clientEventSource,
    this.hasClientMods = false,
    this.launchSignature,
    this.clientHeartbeatSessionId,
    this.clientAppState,
  });

  final String os;
  final String browser;
  final String device;
  final String systemLocale;
  final String browserUserAgent;
  final String browserVersion;
  final String osVersion;
  final String releaseChannel;
  final int clientBuildNumber;
  final int nativeBuildNumber;
  final String? clientEventSource;
  final bool hasClientMods;
  final String clientLaunchId;
  final String? launchSignature;
  final String? clientHeartbeatSessionId;
  final String? clientAppState;

  Map<String, Object?> toJson() => {
    'os': os,
    'browser': browser,
    'device': device,
    'system_locale': systemLocale,
    'browser_user_agent': browserUserAgent,
    'browser_version': browserVersion,
    'os_version': osVersion,
    'release_channel': releaseChannel,
    'client_build_number': clientBuildNumber,
    'native_build_number': nativeBuildNumber,
    'client_event_source': clientEventSource,
    'has_client_mods': hasClientMods,
    'client_launch_id': clientLaunchId,
    'launch_signature': launchSignature,
    'client_heartbeat_session_id': clientHeartbeatSessionId,
    'client_app_state': clientAppState,
  };

  String toBase64() => base64Encode(utf8.encode(jsonEncode(toJson())));
}

final class DiscordDesktopRequestHeaders {
  DiscordDesktopRequestHeaders({
    required String authorization,
    required this.superProperties,
    required this.locale,
    this.fingerprint,
    this.installationId,
    this.acceptLanguage,
    this.timezone,
    this.debugOptions,
    this.routingKey,
    this.clientTraceId,
  }) : _authorization = _requireValue(authorization, 'authorization');

  final String _authorization;
  final DiscordDesktopSuperProperties superProperties;
  final String locale;
  final String? fingerprint;
  final String? installationId;
  final String? acceptLanguage;
  final String? timezone;
  final String? debugOptions;
  final String? routingKey;
  final String? clientTraceId;

  Map<String, String> build() => Map.unmodifiable({
    'Authorization': _authorization,
    'X-Super-Properties': superProperties.toBase64(),
    if (_present(fingerprint)) 'X-Fingerprint': fingerprint!,
    if (_present(installationId)) 'X-Installation-ID': installationId!,
    if (_present(acceptLanguage)) 'Accept-Language': acceptLanguage!,
    'X-Discord-Locale': locale,
    if (_present(timezone)) 'X-Discord-Timezone': timezone!,
    if (_present(debugOptions)) 'X-Debug-Options': debugOptions!,
    if (_present(routingKey)) 'X-Routing-Key': routingKey!,
    if (_present(clientTraceId)) 'x-client-trace-id': clientTraceId!,
  });

  @override
  String toString() => 'DiscordDesktopRequestHeaders(<redacted>)';

  static bool _present(String? value) => value != null && value.isNotEmpty;

  static String _requireValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'Value cannot be empty');
    }
    return normalized;
  }
}
