import 'dart:io';
import 'dart:math';

import '../../domain/chat_repository_factory.dart';
import '../../domain/chat_repository.dart';
import '../../domain/discord_session.dart';
import '../../domain/voice_dave.dart';
import '../dave/native_dave_service.dart';
import '../sqlite_chat_cache.dart';
import 'discord_api_client.dart';
import 'discord_chat_repository.dart';
import 'discord_desktop_api_client.dart';
import 'discord_desktop_chat_repository.dart';
import 'discord_desktop_gateway_client.dart';
import 'discord_desktop_profile.dart';
import 'discord_gateway_client.dart';

final class DiscordRepositoryFactory implements ChatRepositoryFactory {
  const DiscordRepositoryFactory({this.daveService});

  final VoiceDaveService? daveService;

  @override
  Future<ChatRepository> create(DiscordAccountSession session) async {
    return switch (session) {
      DiscordDesktopUserSession() => _createDesktopUser(session),
      DiscordBotSession() => DiscordBotRepositoryFactory(
        daveService: daveService,
      ).create(session),
      _ => throw UnsupportedDiscordSessionException(session.kind),
    };
  }

  Future<ChatRepository> _createDesktopUser(
    DiscordDesktopUserSession session,
  ) async {
    final profile = DiscordDesktopProtocolProfile.installedStable20260725;
    final properties = _desktopProperties(profile);
    final headers = DiscordDesktopRequestHeaders(
      authorization: session.transportCredential,
      superProperties: properties,
      locale: _locale,
      acceptLanguage: '$_locale,en;q=0.9',
      timezone: Platform.environment['TZ'] ?? 'Europe/Budapest',
    ).build();
    final cache = await SqliteChatCache.openDefault();
    return DiscordDesktopChatRepository(
      DiscordDesktopApiClient(
        authorization: session.transportCredential,
        headers: headers,
        baseUri: profile.apiBaseUri,
      ),
      DiscordDesktopGatewayClient(
        authorization: session.transportCredential,
        properties: properties.toJson(),
        profile: profile,
      ),
      cache,
    );
  }

  static String get _locale {
    final locale = Platform.localeName.replaceAll('_', '-');
    return locale.isEmpty ? 'en-US' : locale;
  }

  static DiscordDesktopSuperProperties _desktopProperties(
    DiscordDesktopProtocolProfile profile,
  ) => DiscordDesktopSuperProperties(
    os: Platform.isWindows ? 'Windows' : Platform.operatingSystem,
    systemLocale: _locale,
    browserUserAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) discord/1.0.9249 '
        'Chrome/138.0.7204.251 Electron/37.6.0 Safari/537.36',
    browserVersion: '37.6.0',
    osVersion: Platform.operatingSystemVersion,
    releaseChannel: 'stable',
    clientBuildNumber: profile.clientBuildNumber,
    nativeBuildNumber: 9249,
    clientLaunchId: _launchId(),
    clientAppState: 'focused',
  );

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

final class DiscordBotRepositoryFactory implements ChatRepositoryFactory {
  const DiscordBotRepositoryFactory({this.daveService});

  final VoiceDaveService? daveService;

  @override
  Future<ChatRepository> create(DiscordAccountSession session) async {
    if (session is! DiscordBotSession) {
      throw UnsupportedDiscordSessionException(session.kind);
    }
    final botToken = session.transportCredential;
    final cache = await SqliteChatCache.openDefault();
    return DiscordChatRepository(
      DiscordApiClient(botToken: botToken),
      DiscordGatewayClient(botToken: botToken),
      cache,
      daveService:
          daveService ?? (Platform.isWindows ? NativeDaveService.open() : null),
    );
  }
}
