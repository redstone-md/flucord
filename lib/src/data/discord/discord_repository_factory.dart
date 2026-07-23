import 'dart:io';

import '../../domain/chat_repository.dart';
import '../../domain/voice_dave.dart';
import '../dave/native_dave_service.dart';
import '../sqlite_chat_cache.dart';
import 'discord_api_client.dart';
import 'discord_chat_repository.dart';
import 'discord_gateway_client.dart';

abstract interface class ChatRepositoryFactory {
  Future<ChatRepository> createDiscordRepository(String botToken);
}

final class DiscordRepositoryFactory implements ChatRepositoryFactory {
  const DiscordRepositoryFactory({this.daveService});

  final VoiceDaveService? daveService;

  @override
  Future<ChatRepository> createDiscordRepository(String botToken) async {
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
