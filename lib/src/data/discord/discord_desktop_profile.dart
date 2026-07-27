import 'dart:convert';
import 'dart:io';
import 'dart:math';

final class DiscordDesktopProtocolProfile {
  const DiscordDesktopProtocolProfile({
    required this.clientBuildNumber,
    this.apiVersion = 9,
    this.gatewayVersion = 9,
    this.gatewayCapabilities = 1734653,
    // JSON, not the ETF the installed client uses.
    //
    // The ETF codec is implemented, live-checked against a real HELLO and
    // covered, but it has never decoded a real authenticated READY — and READY
    // is where a payload first exercises the whole term vocabulary at size.
    // Shipping it as the default on that evidence broke login twice. It stays
    // selectable, and becomes the default once a full session has proved it.
    this.gatewayEncoding = 'json',
    this.gatewayCompression = 'zstd-stream',
    this.negotiatedCompression,
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

  /// Transport compression the installed renderer negotiates.
  final String gatewayCompression;

  /// Transport compression Flucord can actually decode.
  ///
  /// `null` connects without a `compress` parameter. Discord's Gateway serves
  /// uncompressed frames in that case, so the observed encoding and state
  /// machine stay intact while the zstd-stream decoder is still missing.
  final String? negotiatedCompression;

  final int maxGuildSubscriptionBytes;
  final String apiHost;
  final String gatewayHost;

  Uri get apiBaseUri => Uri.https(apiHost, '/api/v$apiVersion');

  /// Endpoint the installed desktop client dials.
  Uri gatewayUri({Uri? resumeUri}) =>
      _gatewayUri(resumeUri, gatewayCompression);

  /// Endpoint Flucord dials with the compression it can decode.
  Uri connectionUri({Uri? resumeUri}) =>
      _gatewayUri(resumeUri, negotiatedCompression);

  Uri _gatewayUri(Uri? resumeUri, String? compression) {
    final base = resumeUri ?? Uri(scheme: 'wss', host: gatewayHost);
    return base.replace(
      queryParameters: {
        'encoding': gatewayEncoding,
        'v': '$gatewayVersion',
        'compress': ?compression,
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

final class DiscordDesktopClientContext {
  DiscordDesktopClientContext._({
    required this.profile,
    required this.superProperties,
    required this.locale,
    required this.timezone,
  });

  factory DiscordDesktopClientContext.create({
    DiscordDesktopProtocolProfile profile =
        DiscordDesktopProtocolProfile.installedStable20260725,
  }) {
    final locale = Platform.localeName.replaceAll('_', '-');
    final normalizedLocale = locale.isEmpty ? 'en-US' : locale;
    final userAgent = Platform.isWindows
        ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) discord/1.0.9249 '
              'Chrome/138.0.7204.251 Electron/37.6.0 Safari/537.36'
        : 'Flucord/0.1.0 (${Platform.operatingSystem})';
    return DiscordDesktopClientContext._(
      profile: profile,
      locale: normalizedLocale,
      timezone: Platform.environment['TZ'] ?? 'Europe/Budapest',
      superProperties: DiscordDesktopSuperProperties(
        os: Platform.isWindows ? 'Windows' : Platform.operatingSystem,
        systemLocale: normalizedLocale,
        browserUserAgent: userAgent,
        browserVersion: '37.6.0',
        osVersion: Platform.operatingSystemVersion,
        releaseChannel: 'stable',
        clientBuildNumber: profile.clientBuildNumber,
        nativeBuildNumber: 9249,
        clientLaunchId: _launchId(),
        clientAppState: 'focused',
      ),
    );
  }

  final DiscordDesktopProtocolProfile profile;
  final DiscordDesktopSuperProperties superProperties;
  final String locale;
  final String timezone;

  Map<String, String> unauthenticatedHeaders({String? fingerprint}) => {
    HttpHeaders.acceptHeader: 'application/json',
    HttpHeaders.userAgentHeader: superProperties.browserUserAgent,
    HttpHeaders.acceptLanguageHeader: '$locale,en;q=0.9',
    'X-Super-Properties': superProperties.toBase64(),
    'X-Discord-Locale': locale,
    'X-Discord-Timezone': timezone,
    if (fingerprint != null && fingerprint.isNotEmpty)
      'X-Fingerprint': fingerprint,
  };

  Map<String, String> authenticatedHeaders(
    String authorization, {
    String? fingerprint,
  }) => Map.unmodifiable({
    HttpHeaders.acceptHeader: 'application/json',
    HttpHeaders.userAgentHeader: superProperties.browserUserAgent,
    ...DiscordDesktopRequestHeaders(
      authorization: authorization,
      superProperties: superProperties,
      locale: locale,
      fingerprint: fingerprint,
      acceptLanguage: '$locale,en;q=0.9',
      timezone: timezone,
    ).build(),
  });

  static String _launchId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
