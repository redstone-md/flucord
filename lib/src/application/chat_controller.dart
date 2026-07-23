import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';
import '../domain/voice_connection.dart';
import 'channel_activity_persistence.dart';

part 'chat_controller_events.dart';

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
  final Set<String> _loadingOlderChannels = {};
  final Set<String> _exhaustedChannels = {};
  final Map<String, Object> _olderChannelErrors = {};
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
  VoiceSignalingService? get voiceSignalingService {
    final repository = _repository;
    return repository is VoiceSignalingService
        ? repository as VoiceSignalingService
        : null;
  }

  void setApplicationActive(bool value) {
    if (_isApplicationActive == value) return;
    if (!value && _activeChannelId != null) {
      _workspace = _workspace?.clearChannelUnreadBoundary(_activeChannelId!);
      _persistChannelActivity(_activeChannelId!);
    }
    _isApplicationActive = value;
    if (value && _activeChannelId != null) {
      _workspace = _workspace?.markChannelRead(_activeChannelId!);
      _persistChannelActivity(_activeChannelId!);
      notifyListeners();
    }
  }

  bool isChannelLoading(String channelId) =>
      _loadingChannels.contains(channelId);

  Object? channelError(String channelId) => _channelErrors[channelId];
  bool canLoadOlderMessages(String channelId) =>
      _loadedChannels.contains(channelId) &&
      !_exhaustedChannels.contains(channelId);
  bool isLoadingOlderMessages(String channelId) =>
      _loadingOlderChannels.contains(channelId);
  Object? olderMessagesError(String channelId) =>
      _olderChannelErrors[channelId];
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
    _loadingOlderChannels.clear();
    _exhaustedChannels.clear();
    _olderChannelErrors.clear();
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

  Future<void> openChannel(
    String channelId, {
    bool refresh = false,
    String? anchorMessageId,
  }) async {
    final previousChannelId = _activeChannelId;
    if (previousChannelId != null && previousChannelId != channelId) {
      _workspace = _workspace?.clearChannelUnreadBoundary(previousChannelId);
      _persistChannelActivity(previousChannelId);
    }
    _activeChannelId = channelId;
    _workspace = _workspace?.markChannelRead(channelId);
    _persistChannelActivity(channelId);
    if (_workspace == null ||
        _loadingChannels.contains(channelId) ||
        (_loadedChannels.contains(channelId) && !refresh)) {
      notifyListeners();
      return;
    }
    _loadingChannels.add(channelId);
    _channelErrors.remove(channelId);
    _olderChannelErrors.remove(channelId);
    notifyListeners();
    try {
      final page = await _repository.loadChannelHistory(channelId);
      _workspace = _workspace?.mergeInitialHistory(
        page.history,
        retainExisting: anchorMessageId != null,
      );
      _loadedChannels.add(channelId);
      _setHistoryExhausted(channelId, !page.hasMore);
    } catch (error) {
      _channelErrors[channelId] = error;
    } finally {
      _loadingChannels.remove(channelId);
      if (!_disposed) notifyListeners();
    }
  }

  Future<String?> openDirectConversation(String recipientId) async {
    final value = recipientId.trim();
    if (value.isEmpty || _workspace == null) return null;
    try {
      final conversation = await _repository.openDirectConversation(value);
      _workspace = _workspace!
          .upsertSpace(const CommunitySpace.directMessages())
          .upsertMember(conversation.recipient)
          .upsertChannel(conversation.channel);
      notifyListeners();
      return conversation.channel.id;
    } catch (error) {
      _error = error;
      notifyListeners();
      return null;
    }
  }

  Future<void> loadOlderMessages(String channelId) async {
    final workspace = _workspace;
    if (workspace == null ||
        !canLoadOlderMessages(channelId) ||
        _loadingOlderChannels.contains(channelId)) {
      return;
    }
    final messages = workspace.messagesFor(channelId);
    if (messages.isEmpty) {
      _exhaustedChannels.add(channelId);
      notifyListeners();
      return;
    }
    _loadingOlderChannels.add(channelId);
    _olderChannelErrors.remove(channelId);
    notifyListeners();
    try {
      final page = await _repository.loadChannelHistory(
        channelId,
        beforeMessageId: messages.first.id,
      );
      _workspace = _workspace?.mergeHistory(
        page.history,
        replaceChannel: false,
      );
      _setHistoryExhausted(
        channelId,
        !page.hasMore || page.history.messages.isEmpty,
      );
    } catch (error) {
      _olderChannelErrors[channelId] = error;
    } finally {
      _loadingOlderChannels.remove(channelId);
      if (!_disposed) notifyListeners();
    }
  }

  void _setHistoryExhausted(String channelId, bool exhausted) {
    if (exhausted) {
      _exhaustedChannels.add(channelId);
    } else {
      _exhaustedChannels.remove(channelId);
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
      _workspace = _workspace?.clearChannelUnreadBoundary(channelId);
      _persistChannelActivity(channelId);
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

  void markAllChannelsRead() {
    final workspace = _workspace;
    if (workspace == null) return;
    final activeIds = workspace.channels
        .where((channel) => channel.unread || channel.mentionCount > 0)
        .map((channel) => channel.id)
        .toSet();
    if (activeIds.isEmpty) return;
    _workspace = workspace.copyWith(
      channels: [
        for (final channel in workspace.channels)
          activeIds.contains(channel.id)
              ? channel.markRead().clearUnreadBoundary()
              : channel,
      ],
    );
    for (final channelId in activeIds) {
      _persistChannelActivity(channelId);
    }
    notifyListeners();
  }

  void _clearTyping() {
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _typingMembers.clear();
    _typingRequests.clear();
  }

  void _persistChannelActivity(String channelId) => unawaited(
    ChannelActivityPersistence.save(_repository, _workspace, channelId),
  );

  void _notify() => notifyListeners();

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
