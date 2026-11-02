import 'dart:io';

import '../../domain/chat_repository_factory.dart';
import '../../domain/chat_repository.dart';
import '../../domain/discord_session.dart';
import '../../domain/voice_dave.dart';
import '../chat_image_cache.dart';
import '../dave/native_dave_service.dart';
import '../sqlite_chat_cache.dart';
import 'discord_api_client.dart';
import 'discord_chat_repository.dart';
import 'discord_desktop_api_client.dart';
import 'discord_desktop_chat_repository.dart';
import 'discord_desktop_gateway_client.dart';
import 'discord_desktop_profile.dart';
import 'discord_gateway_client.dart';

/// Both transports share one cache file.
Future<void> _clearDefaultCache() async {
  final cache = await SqliteChatCache.openDefault();
  try {
    await cache.clear();
  } finally {
    await cache.close();
  }
}

final class DiscordRepositoryFactory implements ChatRepositoryFactory {
  const DiscordRepositoryFactory({this.daveService});

  final VoiceDaveService? daveService;

  @override
  Future<void> clearCache() => _clearDefaultCache();

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
    final context = DiscordDesktopClientContext.create(profile: profile);
    final headers = context.authenticatedHeaders(session.transportCredential);
    final cache = await SqliteChatCache.openDefault();
    return DiscordDesktopChatRepository(
      DiscordDesktopApiClient(
        authorization: session.transportCredential,
        headers: headers,
        baseUri: profile.apiBaseUri,
      ),
      DiscordDesktopGatewayClient(
        authorization: session.transportCredential,
        properties: context.superProperties.toJson(),
        profile: profile,
      ),
      cache,
      accountId: session.accountId,
      daveService: _resolveDaveService(),
      clearChatImages: ChatImageCache.clear,
    );
  }

  /// Voice media on Discord is end-to-end encrypted, so a session without DAVE
  /// has no voice at all rather than unencrypted voice. The native library is
  /// Windows-only today; elsewhere the join fails loudly instead of silently
  /// downgrading.
  VoiceDaveService? _resolveDaveService() =>
      daveService ?? (Platform.isWindows ? NativeDaveService.open() : null);
}

final class DiscordBotRepositoryFactory implements ChatRepositoryFactory {
  const DiscordBotRepositoryFactory({this.daveService});

  final VoiceDaveService? daveService;

  @override
  Future<void> clearCache() => _clearDefaultCache();

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
      accountId: session.accountId,
      daveService:
          daveService ?? (Platform.isWindows ? NativeDaveService.open() : null),
      clearChatImages: ChatImageCache.clear,
    );
  }
}
