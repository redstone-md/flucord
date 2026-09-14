import 'dart:async';

import '../../domain/chat_repository.dart';

extension DiscordRepositoryEvents on StreamController<ChatRepositoryEvent> {
  void addStatus(RepositoryConnectionStatus status) {
    if (!isClosed) add(RepositoryStatusChangedEvent(status));
  }
}
