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
  final StreamController<MessageUpsertedEvent> _incomingMessages =
      StreamController.broadcast();

  ChatLoadState _state = ChatLoadState.idle;
  ChatWorkspace? _workspace;
  Object? _error;
  bool _isSending = false;
  RepositoryConnectionStatus _connectionStatus =
      RepositoryConnectionStatus.offline;
  final Set<String> _loadedChannels = {};
  final Set<String> _loadingChannels = {};
  final Map<String, Object> _channelErrors = {};
  final Map<String, ChannelHistory> _pinnedMessages = {};
  final Set<String> _loadingPins = {};
  final Map<String, Object> _pinErrors = {};
  final Map<String, Set<String>> _typingMembers = {};
  final Map<String, Timer> _typingTimers = {};
  final Map<String, DateTime> _typingRequests = {};
  String? _activeChannelId;
  bool _isApplicationActive = true;
  bool _disposed = false;

  ChatLoadState get state => _state;
  ChatWorkspace? get workspace => _workspace;
  Object? get error => _error;
  bool get isSending => _isSending;
  RepositoryConnectionStatus get connectionStatus => _connectionStatus;
  String? get activeChannelId => _activeChannelId;
  Stream<MessageUpsertedEvent> get incomingMessages => _incomingMessages.stream;

  void setApplicationActive(bool value) {
    if (_isApplicationActive == value) return;
    _isApplicationActive = value;
    if (value && _activeChannelId != null) {
      _workspace = _workspace?.markChannelRead(_activeChannelId!);
      notifyListeners();
    }
  }

  bool isChannelLoading(String channelId) =>
      _loadingChannels.contains(channelId);

  Object? channelError(String channelId) => _channelErrors[channelId];
  ChannelHistory? pinnedMessages(String channelId) =>
      _pinnedMessages[channelId];
  bool isLoadingPins(String channelId) => _loadingPins.contains(channelId);
  Object? pinError(String channelId) => _pinErrors[channelId];

  List<Member> typingMembersFor(String channelId) {
    final workspace = _workspace;
    if (workspace == null) return const [];
    return (_typingMembers[channelId] ?? const <String>{})
        .where((id) => id != workspace.currentMemberId)
        .map(workspace.memberOrNull)
        .whereType<Member>()
        .toList(growable: false);
  }

  Future<void> useRepository(ChatRepository repository) async {
    await _eventSubscription?.cancel();
    await _repository.close();
    _repository = repository;
    _workspace = null;
    _loadedChannels.clear();
    _loadingChannels.clear();
    _channelErrors.clear();
    _pinnedMessages.clear();
    _loadingPins.clear();
    _pinErrors.clear();
    _clearTyping();
    _activeChannelId = null;
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
    _activeChannelId = channelId;
    _workspace = _workspace?.markChannelRead(channelId);
    if (_workspace == null ||
        _loadingChannels.contains(channelId) ||
        (_loadedChannels.contains(channelId) && !refresh)) {
      notifyListeners();
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
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadPinnedMessages(
    String channelId, {
    bool refresh = false,
  }) async {
    if (_loadingPins.contains(channelId) ||
        (_pinnedMessages.containsKey(channelId) && !refresh)) {
      return;
    }
    _loadingPins.add(channelId);
    _pinErrors.remove(channelId);
    notifyListeners();
    try {
      final history = await _repository.loadPinnedMessages(channelId);
      _pinnedMessages[channelId] = history;
      for (final member in history.members) {
        _workspace = _workspace?.upsertMember(member);
      }
    } catch (error) {
      _pinErrors[channelId] = error;
    } finally {
      _loadingPins.remove(channelId);
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> sendMessage({
    required String channelId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
  }) async {
    final workspace = _workspace;
    final content = body.trim();
    if (workspace == null ||
        (content.isEmpty && attachments.isEmpty) ||
        _isSending) {
      return false;
    }

    _isSending = true;
    notifyListeners();
    try {
      final message = await _repository.sendMessage(
        channelId: channelId,
        authorId: workspace.currentMemberId,
        body: content,
        attachments: attachments,
        replyToMessageId: replyToMessageId,
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

  Future<bool> editMessage(ChatMessage message, String body) async {
    final content = body.trim();
    if (content.isEmpty || _isSending) return false;
    _isSending = true;
    notifyListeners();
    try {
      final updated = await _repository.editMessage(
        channelId: message.channelId,
        messageId: message.id,
        body: content,
      );
      _workspace = _workspace?.upsertMessage(updated);
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> deleteMessage(ChatMessage message) async {
    try {
      await _repository.deleteMessage(
        channelId: message.channelId,
        messageId: message.id,
      );
      _workspace = _workspace?.removeMessage(message.id);
    } catch (error) {
      _error = error;
    }
    notifyListeners();
  }

  Future<void> toggleReaction(ChatMessage message, MessageReaction reaction) =>
      reaction.reactedByCurrentUser
      ? _repository.removeReaction(
          channelId: message.channelId,
          messageId: message.id,
          emoji: reaction.key,
        )
      : _repository.addReaction(
          channelId: message.channelId,
          messageId: message.id,
          emoji: reaction.key,
        );

  Future<void> addReaction(ChatMessage message, String emoji) =>
      _repository.addReaction(
        channelId: message.channelId,
        messageId: message.id,
        emoji: emoji,
      );

  Future<void> togglePin(ChatMessage message) async {
    try {
      if (message.isPinned) {
        await _repository.unpinMessage(
          channelId: message.channelId,
          messageId: message.id,
        );
      } else {
        await _repository.pinMessage(
          channelId: message.channelId,
          messageId: message.id,
        );
      }
      final updated = message.copyWith(isPinned: !message.isPinned);
      _workspace = _workspace?.upsertMessage(updated);
      final pins = _pinnedMessages[message.channelId];
      if (pins != null) {
        final messages = message.isPinned
            ? pins.messages.where((item) => item.id != message.id).toList()
            : [updated, ...pins.messages];
        _pinnedMessages[message.channelId] = ChannelHistory(
          channelId: message.channelId,
          messages: messages,
          members: pins.members,
        );
      }
    } catch (error) {
      _error = error;
    }
    notifyListeners();
  }

  Future<void> startTyping(String channelId) async {
    final now = DateTime.now();
    final previous = _typingRequests[channelId];
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 8)) {
      return;
    }
    _typingRequests[channelId] = now;
    try {
      await _repository.startTyping(channelId);
    } catch (error) {
      _error = error;
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
          if (event.isNew &&
              event.message.authorId != _workspace?.currentMemberId) {
            _incomingMessages.add(event);
            if (!_isApplicationActive ||
                event.message.channelId != _activeChannelId) {
              _workspace = _workspace?.markChannelUnread(
                event.message.channelId,
                mention: event.mentionsCurrentMember,
              );
            }
          }
        case MessageDeletedEvent():
          _workspace = _workspace?.removeMessage(event.messageId);
        case ChannelUpsertedEvent():
          _workspace = _workspace?.upsertChannel(event.channel);
        case ChannelDeletedEvent():
          _workspace = _workspace?.removeChannel(event.channelId);
        case MemberUpsertedEvent():
          _workspace = _workspace?.upsertMember(event.member);
        case MemberRemovedEvent():
          _workspace = _workspace?.removeMemberFromSpace(
            event.memberId,
            event.spaceId,
          );
        case PresenceChangedEvent():
          _workspace = _workspace?.updatePresence(
            event.memberId,
            event.presence,
          );
        case TypingStartedEvent():
          _handleTyping(event);
        case PinsChangedEvent():
          if (_pinnedMessages.containsKey(event.channelId)) {
            unawaited(loadPinnedMessages(event.channelId, refresh: true));
          }
        case RepositoryStatusChangedEvent():
          _connectionStatus = event.status;
      }
      notifyListeners();
    });
  }

  void _handleTyping(TypingStartedEvent event) {
    if (event.memberId == _workspace?.currentMemberId) return;
    final members = _typingMembers.putIfAbsent(event.channelId, () => {});
    members.add(event.memberId);
    final key = '${event.channelId}:${event.memberId}';
    _typingTimers[key]?.cancel();
    _typingTimers[key] = Timer(const Duration(seconds: 9), () {
      _typingMembers[event.channelId]?.remove(event.memberId);
      _typingTimers.remove(key);
      if (!_disposed) notifyListeners();
    });
  }

  void _clearTyping() {
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _typingMembers.clear();
    _typingRequests.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _clearTyping();
    unawaited(_eventSubscription?.cancel());
    unawaited(_repository.close());
    unawaited(_incomingMessages.close());
    super.dispose();
  }
}
