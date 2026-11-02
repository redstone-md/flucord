import 'chat_repository.dart';
import 'discord_session.dart';

abstract interface class ChatRepositoryFactory {
  Future<ChatRepository> create(DiscordAccountSession session);

  /// Removes what the repositories of this factory cached on disk.
  ///
  /// It works with no repository open, because a sign-out can come after the
  /// session has already gone. Do not call it while a repository is open: that
  /// repository would keep writing.
  Future<void> clearCache();
}

final class UnsupportedDiscordSessionException implements Exception {
  const UnsupportedDiscordSessionException(this.kind);

  final DiscordSessionKind kind;

  @override
  String toString() => 'Unsupported Discord chat session: ${kind.name}';
}
