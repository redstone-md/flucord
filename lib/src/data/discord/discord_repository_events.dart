import 'dart:async';

import '../../domain/chat_repository.dart';

extension DiscordRepositoryEvents on StreamController<ChatRepositoryEvent> {
  void addStatus(RepositoryConnectionStatus status) =>
      publish(RepositoryStatusChangedEvent(status));

  /// Adds [event] unless the repository has closed, which it may have done
  /// while a handler was waiting on the cache.
  void publish(ChatRepositoryEvent event) {
    if (!isClosed) add(event);
  }
}
