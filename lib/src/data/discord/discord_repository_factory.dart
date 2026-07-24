import 'dart:io';

import '../../domain/chat_repository_factory.dart';
import '../../domain/chat_repository.dart';
import '../../domain/discord_session.dart';
import '../../domain/voice_dave.dart';
import '../dave/native_dave_service.dart';
import '../sqlite_chat_cache.dart';
import 'discord_api_client.dart';
import 'discord_chat_repository.dart';
import 'discord_gateway_client.dart';

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
