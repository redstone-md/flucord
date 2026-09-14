import 'chat_repository.dart';
import 'discord_session.dart';

abstract interface class ChatRepositoryFactory {
  Future<ChatRepository> create(DiscordAccountSession session);
}

final class UnsupportedDiscordSessionException implements Exception {
  const UnsupportedDiscordSessionException(this.kind);

  final DiscordSessionKind kind;

  @override
  String toString() => 'Unsupported Discord chat session: ${kind.name}';
}
