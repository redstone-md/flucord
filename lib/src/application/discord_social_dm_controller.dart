import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/discord_relationship.dart';
import '../domain/discord_social_dm.dart';
import '../domain/discord_social_sdk.dart';

enum DiscordSocialDmLoadState {
  idle,
  loading,
  ready,
  authorizationRequired,
  unavailable,
  failure,
}

final class DiscordSocialDmController extends ChangeNotifier {
  DiscordSocialDmController(this._gateway) {
    if (_gateway case final DiscordSocialDmEvents events) {
      _eventSubscription = events.socialDmEvents.listen(_applyEvent);
    }
  }

  final DiscordSocialDmGateway _gateway;
  StreamSubscription<DiscordSocialDmEvent>? _eventSubscription;

  DiscordSocialDmLoadState _state = DiscordSocialDmLoadState.idle;
  List<DiscordSocialDmConversation> _conversations = const [];
  final Map<String, List<DiscordSocialDmMessage>> _messages = {};
  final Set<String> _loadingUserIds = {};
  final Set<String> _sendingUserIds = {};
  final Set<String> _mutatingMessageIds = {};
  final Map<String, String> _messageErrors = {};
  final Map<String, String> _messageActionErrors = {};
  Future<void>? _conversationLoad;
  bool _sdkReady = false;
  bool _authenticated = false;
  bool _initialized = false;
  bool _showingChat = false;
  bool _disposed = false;
  int _generation = 0;

  DiscordSocialDmLoadState get state => _state;
  List<DiscordSocialDmConversation> get conversations => _conversations;
  List<DiscordSocialDmMessage> messagesFor(String userId) =>
      _messages[userId] ?? const [];
  bool isLoadingMessages(String userId) => _loadingUserIds.contains(userId);
  bool isSending(String userId) => _sendingUserIds.contains(userId);
  bool isMutatingMessage(String messageId) =>
      _mutatingMessageIds.contains(messageId);
  String? messageErrorFor(String userId) => _messageErrors[userId];
  String? messageActionErrorFor(String messageId) =>
      _messageActionErrors[messageId];

  DiscordSocialDmConversation? conversationFor(String userId) {
    for (final conversation in _conversations) {
      if (conversation.user.id == userId) return conversation;
    }
    return null;
  }

  void reconcileSession(
    DiscordSocialSdkAvailability? availability, {
    required bool authenticated,
  }) {
    final sdkReady = availability?.isReady ?? false;
    final nextAuthenticated = sdkReady && authenticated;
    if (_sdkReady == sdkReady && _authenticated == nextAuthenticated) return;
    if (_showingChat) unawaited(setShowingChat(false));
    _sdkReady = sdkReady;
    _authenticated = nextAuthenticated;
    _initialized = false;
    _conversationLoad = null;
    _generation++;
    _loadingUserIds.clear();
    _sendingUserIds.clear();
    _mutatingMessageIds.clear();
    _messageErrors.clear();
    _messageActionErrors.clear();
    if (!sdkReady) {
      _clear(DiscordSocialDmLoadState.unavailable);
      return;
    }
    if (!nextAuthenticated) {
      _clear(DiscordSocialDmLoadState.authorizationRequired);
      return;
    }
    _state = DiscordSocialDmLoadState.idle;
    notifyListeners();
    unawaited(initialize());
  }

  Future<void> initialize() {
    if (_initialized || !_authenticated || _disposed) {
      return _conversationLoad ?? Future<void>.value();
    }
    _initialized = true;
    return _startConversationLoad();
  }

  Future<void> retry() =>
      _authenticated ? _startConversationLoad() : Future<void>.value();

  Future<void> loadMessages(String userId, {bool refresh = false}) async {
    if (!_authenticated ||
        _disposed ||
        _loadingUserIds.contains(userId) ||
        (!refresh && _messages.containsKey(userId))) {
      return;
    }
    final generation = _generation;
    _loadingUserIds.add(userId);
    _messageErrors.remove(userId);
    notifyListeners();
    try {
      final messages = await _gateway.fetchMessages(userId: userId);
      if (!_accepts(generation)) return;
      _messages[userId] = _sortedMessages(messages);
    } on DiscordSocialSdkException catch (error) {
      if (_accepts(generation)) _messageErrors[userId] = error.code;
    } on Object {
      if (_accepts(generation)) _messageErrors[userId] = 'message_load_failed';
    } finally {
      if (_accepts(generation)) {
        _loadingUserIds.remove(userId);
        notifyListeners();
      }
    }
  }

  Future<bool> sendMessage(String userId, String content) async {
    if (!_authenticated ||
        _disposed ||
        content.trim().isEmpty ||
        content.length > 2000 ||
        _sendingUserIds.contains(userId)) {
      return false;
    }
    final generation = _generation;
    _sendingUserIds.add(userId);
    _messageErrors.remove(userId);
    notifyListeners();
    try {
      await _gateway.sendMessage(userId: userId, content: content);
      if (!_accepts(generation)) return false;
      await loadMessages(userId, refresh: true);
      unawaited(_startConversationLoad(silent: true));
      return true;
    } on DiscordSocialSdkException catch (error) {
      if (_accepts(generation)) _messageErrors[userId] = error.code;
      return false;
    } on Object {
      if (_accepts(generation)) _messageErrors[userId] = 'message_send_failed';
      return false;
    } finally {
      if (_accepts(generation)) {
        _sendingUserIds.remove(userId);
        notifyListeners();
      }
    }
  }

  Future<bool> editMessage(String userId, String messageId, String content) {
    if (content.trim().isEmpty || content.length > 2000) {
      return Future.value(false);
    }
    return _mutateMessage(
      userId: userId,
      messageId: messageId,
      operation: () => _gateway.editMessage(
        userId: userId,
        messageId: messageId,
        content: content,
      ),
      replacementContent: content,
      refreshAfterSuccess: true,
    );
  }

  Future<bool> deleteMessage(String userId, String messageId) => _mutateMessage(
    userId: userId,
    messageId: messageId,
    operation: () =>
        _gateway.deleteMessage(userId: userId, messageId: messageId),
    removeAfterSuccess: true,
  );

  Future<void> setShowingChat(bool showing) async {
    if (_disposed || !_authenticated || _showingChat == showing) return;
    _showingChat = showing;
    try {
      await _gateway.setShowingChat(showing);
    } on Object {
      if (showing && !_disposed && _showingChat) _showingChat = false;
    }
  }

  void ensureConversation(DiscordRelationshipUser user) {
    if (conversationFor(user.id) != null) return;
    _conversations = List.unmodifiable([
      DiscordSocialDmConversation(user: user, lastMessageId: '0'),
      ..._conversations,
    ]);
    notifyListeners();
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (!_authenticated || _disposed) return;
    final generation = _generation;
    if (!silent) {
      _state = DiscordSocialDmLoadState.loading;
      notifyListeners();
    }
    try {
      final conversations = await _gateway.fetchConversations();
      if (!_accepts(generation)) return;
      _conversations = _sortedConversations(conversations);
      _state = DiscordSocialDmLoadState.ready;
    } on DiscordSocialSdkException catch (error) {
      if (!_accepts(generation)) return;
      _state = error.code == 'not_authenticated'
          ? DiscordSocialDmLoadState.authorizationRequired
          : DiscordSocialDmLoadState.failure;
    } on Object {
      if (!_accepts(generation)) return;
      _state = DiscordSocialDmLoadState.failure;
    }
    notifyListeners();
  }

  void _applyEvent(DiscordSocialDmEvent event) {
    if (!_authenticated || _disposed) return;
    final message = event.message;
    if (event.type == DiscordSocialDmEventType.deleted || message == null) {
      _removeMessage(event.messageId);
      notifyListeners();
      return;
    }
    final userId = message.conversationUserId;
    final existing = _messages[userId];
    if (existing != null) {
      _messages[userId] = _sortedMessages([
        ...existing.where((item) => item.id != message.id),
        message,
      ]);
    }
    unawaited(_startConversationLoad(silent: true));
    notifyListeners();
  }

  Future<void> _startConversationLoad({bool silent = false}) {
    final active = _conversationLoad;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _loadConversations(silent: silent).whenComplete(() {
      if (identical(_conversationLoad, operation)) _conversationLoad = null;
    });
    _conversationLoad = operation;
    return operation;
  }

  Future<bool> _mutateMessage({
    required String userId,
    required String messageId,
    required Future<void> Function() operation,
    bool refreshAfterSuccess = false,
    bool removeAfterSuccess = false,
    String? replacementContent,
  }) async {
    final message = _messageFor(userId, messageId);
    if (!_authenticated ||
        _disposed ||
        message?.authoredByCurrentUser != true ||
        _mutatingMessageIds.contains(messageId)) {
      return false;
    }
    final generation = _generation;
    _mutatingMessageIds.add(messageId);
    _messageActionErrors.remove(messageId);
    notifyListeners();
    try {
      await operation();
      if (!_accepts(generation)) return false;
      if (removeAfterSuccess) _removeMessage(messageId);
      if (replacementContent != null) {
        _replaceMessageContent(userId, messageId, replacementContent);
      }
      if (refreshAfterSuccess) await loadMessages(userId, refresh: true);
      return true;
    } on DiscordSocialSdkException catch (error) {
      if (_accepts(generation)) _messageActionErrors[messageId] = error.code;
      return false;
    } on Object {
      if (_accepts(generation)) {
        _messageActionErrors[messageId] = 'message_mutation_failed';
      }
      return false;
    } finally {
      if (_accepts(generation)) {
        _mutatingMessageIds.remove(messageId);
        notifyListeners();
      }
    }
  }

  DiscordSocialDmMessage? _messageFor(String userId, String messageId) {
    for (final message in _messages[userId] ?? const []) {
      if (message.id == messageId) return message;
    }
    return null;
  }

  void _removeMessage(String messageId) {
    for (final userId in _messages.keys.toList(growable: false)) {
      _messages[userId] = List.unmodifiable(
        _messages[userId]!.where((item) => item.id != messageId),
      );
    }
  }

  void _replaceMessageContent(String userId, String messageId, String content) {
    final messages = _messages[userId];
    if (messages == null) return;
    _messages[userId] = List.unmodifiable([
      for (final message in messages)
        if (message.id == messageId) message.withContent(content) else message,
    ]);
  }

  void _clear(DiscordSocialDmLoadState nextState) {
    _conversations = const [];
    _messages.clear();
    _state = nextState;
    if (!_disposed) notifyListeners();
  }

  bool _accepts(int generation) =>
      !_disposed && _authenticated && generation == _generation;

  static List<DiscordSocialDmConversation> _sortedConversations(
    Iterable<DiscordSocialDmConversation> conversations,
  ) => List.unmodifiable(
    conversations.toList()..sort((left, right) {
      final leftId = BigInt.tryParse(left.lastMessageId) ?? BigInt.zero;
      final rightId = BigInt.tryParse(right.lastMessageId) ?? BigInt.zero;
      return rightId.compareTo(leftId);
    }),
  );

  static List<DiscordSocialDmMessage> _sortedMessages(
    Iterable<DiscordSocialDmMessage> messages,
  ) => List.unmodifiable(
    messages.toList()..sort((left, right) {
      final timestamp = left.sentAt.compareTo(right.sentAt);
      return timestamp != 0 ? timestamp : left.id.compareTo(right.id);
    }),
  );

  @override
  void dispose() {
    if (_showingChat) unawaited(setShowingChat(false));
    _disposed = true;
    _generation++;
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }
}
