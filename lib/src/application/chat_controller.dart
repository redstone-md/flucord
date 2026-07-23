import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';

enum ChatLoadState { idle, loading, ready, failure }

final class ChatController extends ChangeNotifier {
  ChatController(ChatRepository repository) : _repository = repository {
    _listenToRepository();
  }

  ChatRepository _repository;
  StreamSubscription<ChatRepositoryEvent>? _eventSubscription;

  ChatLoadState _state = ChatLoadState.idle;
  ChatWorkspace? _workspace;
  Object? _error;
  bool _isSending = false;
  RepositoryConnectionStatus _connectionStatus =
      RepositoryConnectionStatus.offline;
  final Set<String> _loadedChannels = {};
  final Set<String> _loadingChannels = {};
  final Map<String, Object> _channelErrors = {};

  ChatLoadState get state => _state;
  ChatWorkspace? get workspace => _workspace;
  Object? get error => _error;
  bool get isSending => _isSending;
  RepositoryConnectionStatus get connectionStatus => _connectionStatus;

  bool isChannelLoading(String channelId) =>
      _loadingChannels.contains(channelId);

  Object? channelError(String channelId) => _channelErrors[channelId];

  Future<void> useRepository(ChatRepository repository) async {
    await _eventSubscription?.cancel();
    await _repository.close();
    _repository = repository;
    _workspace = null;
    _loadedChannels.clear();
    _loadingChannels.clear();
    _channelErrors.clear();
    _connectionStatus = RepositoryConnectionStatus.offline;
    _listenToRepository();
    await load();
    if (_state == ChatLoadState.failure) {
      throw _error!;
    }
  }

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
    final workspace = _workspace;
    if (_state == ChatLoadState.ready && workspace != null) {
      final textChannels = workspace.channels.where(
        (channel) => channel.kind == ChannelKind.text,
      );
      if (textChannels.isNotEmpty) {
        unawaited(openChannel(textChannels.first.id));
      }
    }
  }

  Future<void> openChannel(String channelId, {bool refresh = false}) async {
    if (_workspace == null ||
        _loadingChannels.contains(channelId) ||
        (_loadedChannels.contains(channelId) && !refresh)) {
      return;
    }
    _loadingChannels.add(channelId);
    _channelErrors.remove(channelId);
    notifyListeners();
    try {
      final history = await _repository.loadChannelHistory(channelId);
      _workspace = _workspace?.mergeHistory(history);
      _loadedChannels.add(channelId);
    } catch (error) {
      _channelErrors[channelId] = error;
    } finally {
      _loadingChannels.remove(channelId);
      notifyListeners();
    }
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
      _workspace = _workspace?.upsertMessage(message);
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  void _listenToRepository() {
    _eventSubscription = _repository.events.listen((event) {
      switch (event) {
        case MessageUpsertedEvent():
          _workspace = _workspace?.upsertMessage(
            event.message,
            member: event.member,
          );
        case RepositoryStatusChangedEvent():
          _connectionStatus = event.status;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    unawaited(_repository.close());
    super.dispose();
  }
}
