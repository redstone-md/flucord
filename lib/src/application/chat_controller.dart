import '../domain/multi_factor_auth.dart';
import '../domain/auth_session.dart';
import '../domain/family_centre.dart';
import '../domain/account_standing.dart';
import '../domain/automod_rule.dart';
import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';
import '../domain/discord_permissions.dart';
import '../domain/discord_snowflake.dart';
import '../domain/forum_repository.dart';
import '../domain/guild_management_repository.dart';
import '../domain/guild_member_list_repository.dart';
import '../domain/moderation_repository.dart';
import '../domain/message_forward_repository.dart';
import '../domain/message_flag_repository.dart';
import '../domain/message_search_repository.dart';
import '../domain/poll_repository.dart';
import '../domain/presence_repository.dart';
import '../domain/reaction_repository.dart';
import '../domain/read_state.dart';
import '../domain/read_state_repository.dart';
import '../domain/scheduled_event_repository.dart';
import '../domain/sticker_repository.dart';
import '../domain/application_command.dart';
import '../domain/conversation_summary.dart';
import '../domain/go_live_stream.dart';
import '../domain/message_component.dart';
import '../domain/gif_picker.dart';
import '../domain/soundboard.dart';
import '../domain/stage_channel.dart';
import '../domain/thread_membership.dart';
import '../domain/thread_repository.dart';
import '../domain/user_profile.dart';
import '../domain/user_settings_repository.dart';
import '../domain/voice_call.dart';
import '../domain/voice_connection.dart';
import '../domain/voice_message_recorder.dart';
import '../domain/voice_message_repository.dart';
import '../domain/workspace_permissions.dart';
import 'channel_activity_persistence.dart';

part 'chat_controller_events.dart';
part 'chat_controller_typing.dart';
part 'chat_controller_threads.dart';
part 'chat_controller_forums.dart';
part 'chat_controller_polls.dart';
part 'chat_controller_reactions.dart';
part 'chat_controller_forwards.dart';
part 'chat_controller_message_flags.dart';
part 'chat_controller_stickers.dart';
part 'chat_controller_voice_messages.dart';
part 'chat_controller_scheduled_events.dart';
part 'chat_controller_user_settings.dart';
part 'chat_controller_read_state.dart';

enum ChatLoadState { idle, loading, ready, failure }

final class ChatController extends ChangeNotifier {
  ChatController(ChatRepository repository) : _repository = repository {
    _listenToRepository();
  }

  ChatRepository _repository;
  StreamSubscription<ChatRepositoryEvent>? _eventSubscription;
  StreamSubscription<ReadStateSnapshot>? _readStateSubscription;
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
  final Map<String, List<GuildScheduledEvent>> _scheduledEventsBySpace = {};
  final Set<String> _loadingScheduledEventSpaces = {};
  final Map<String, Object> _scheduledEventErrors = {};
  final Map<String, Set<String>> _typingMembers = {};
  final Map<String, Timer> _typingTimers = {};
  final Map<String, DateTime> _typingRequests = {};
  final _archivedThreadState = _ArchivedThreadState();
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
  VoiceSignalingService? get voiceSignalingService =>
      _repository.voiceSignaling;

  /// The private-call plane of the active transport, when it has one.
  DirectCallService? get directCallService => _repository.directCalls;

  /// The server-side search plane of the active transport, when it has one.
  ///
  /// Read through the repository on every call rather than cached, because the
  /// transport is replaced whenever the session changes and a stale search
  /// plane would query the account that just signed out.
  MessageSearchRepository? get messageSearch => _repository.messageSearch;

  /// The presence plane of the active transport, when it has one.
  PresenceService? get presenceService => _repository.presence;

  /// The lazy member-list surface, when the active transport offers one.
  ///
  /// Only the desktop-user transport can serve rosters; every other transport
  /// reports `null` so the member panel falls back to what the workspace
  /// already knows rather than waiting for rows that will never arrive.
  GuildMemberListRepository? get memberListRepository {
    final repository = _repository;
    return repository is GuildMemberListRepository
        ? repository as GuildMemberListRepository
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
      // R04 lists window focus among the triggers that acknowledge the open
      // channel; without it a message read while the app was hidden stays
      // unread on every other device.
      acknowledgeChannel(_activeChannelId!);
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

  Future<void> useRepository(ChatRepository repository) async {
    await _eventSubscription?.cancel();
    await _readStateSubscription?.cancel();
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
    _scheduledEventsBySpace.clear();
    _loadingScheduledEventSpaces.clear();
    _scheduledEventErrors.clear();
    _archivedThreadState.clear();
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
      await _loadScheduledEventsForWorkspace();
      _state = ChatLoadState.ready;
    } catch (error) {
      _error = error;
      _state = ChatLoadState.failure;
    }
    notifyListeners();
    final workspace = _workspace;
    if (_state == ChatLoadState.ready && workspace != null) {
      // A voice channel does carry messages, but it is never the channel the
      // app lands on unasked, so warming its history here would be wasted work.
      // The same visibility filter the shell lands by is applied here, or the
      // two would disagree and the channel actually shown would never load.
      final permissions = WorkspacePermissions(workspace);
      final textChannels = workspace.channels.where(
        (channel) =>
            channel.kind != ChannelKind.voice &&
            !channel.isThread &&
            permissions.can(DiscordPermissions.viewChannel, channel),
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
    acknowledgeChannel(channelId);
    final channel = _workspace?.channelOrNull(channelId);
    if (channel?.kind == ChannelKind.forum ||
        channel?.kind == ChannelKind.media) {
      notifyListeners();
      await loadArchivedThreads(channelId, refresh: refresh);
      return;
    }
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
      // The page may name a newer message than the channel record did, and the
      // channel is on screen either way, so the cursor is moved again here.
      acknowledgeChannel(channelId);
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
    bool suppressNotifications = false,
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
        suppressNotifications: suppressNotifications,
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
    if (!message.canEdit || content.isEmpty || _isSending) return false;
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

  /// Acts on an AutoMod alert from the alert itself.
  ///
  /// The guild comes from the channel the alert sits in rather than from the
  /// caller: an alert is always in a guild channel, and asking the surface to
  /// supply an id it would have to look up here anyway is how the two end up
  /// disagreeing.
  Future<void> resolveAutoModAlert(
    ChatMessage message,
    AutoModAlertAction action,
  ) async {
    final guildId = _channelById(message.channelId)?.spaceId;
    if (guildId == null || guildId.isEmpty) return;
    try {
      await _repository.resolveAutoModAlert(
        guildId: guildId,
        channelId: message.channelId,
        messageId: message.id,
        action: action,
      );
    } catch (error) {
      _error = error;
    }
    notifyListeners();
  }

  ConversationChannel? _channelById(String channelId) {
    for (final channel
        in _workspace?.channels ?? const <ConversationChannel>[]) {
      if (channel.id == channelId) return channel;
    }
    return null;
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

  void _persistChannelActivity(String channelId) => unawaited(
    ChannelActivityPersistence.save(_repository, _workspace, channelId),
  );

  void _notify() => notifyListeners();

  @override
  void dispose() {
    _disposed = true;
    _clearTyping();
    unawaited(_readStateSubscription?.cancel());
    unawaited(_eventSubscription?.cancel());
    unawaited(_repository.close());
    unawaited(_incomingMessages.close());
    super.dispose();
  }
}
