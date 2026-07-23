import 'package:flutter/foundation.dart';

import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';

enum ChatLoadState { idle, loading, ready, failure }

final class ChatController extends ChangeNotifier {
  ChatController(this._repository);

  final ChatRepository _repository;

  ChatLoadState _state = ChatLoadState.idle;
  ChatWorkspace? _workspace;
  Object? _error;
  bool _isSending = false;

  ChatLoadState get state => _state;
  ChatWorkspace? get workspace => _workspace;
  Object? get error => _error;
  bool get isSending => _isSending;

  Future<void> load() async {
    _state = ChatLoadState.loading;
    _error = null;
    notifyListeners();
    try {
      _workspace = await _repository.loadWorkspace();
      _state = ChatLoadState.ready;
    } catch (error) {
      _error = error;
      _state = ChatLoadState.failure;
    }
    notifyListeners();
  }

  Future<bool> sendMessage({
    required String channelId,
    required String body,
  }) async {
    final workspace = _workspace;
    final content = body.trim();
    if (workspace == null || content.isEmpty || _isSending) {
      return false;
    }

    _isSending = true;
    notifyListeners();
    try {
      final message = await _repository.sendMessage(
        channelId: channelId,
        authorId: workspace.currentMemberId,
        body: content,
      );
      _workspace = workspace.copyWith(
        messages: [...workspace.messages, message],
      );
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }
}
