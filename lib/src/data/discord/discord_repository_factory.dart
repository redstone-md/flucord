import 'dart:io';

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
    );
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
