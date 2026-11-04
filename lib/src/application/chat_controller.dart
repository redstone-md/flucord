import '../domain/game_detection.dart';
import '../domain/desktop_relationship_repository.dart';
import '../domain/age_verification.dart';
import '../domain/multi_factor_auth.dart';
import '../domain/auth_session.dart';
import '../domain/family_centre.dart';
import '../domain/account_connections.dart';
import '../domain/account_data_package.dart';
import '../domain/account_entitlements.dart';
import '../domain/app_authorisation.dart';
import '../domain/account_standing.dart';
import '../domain/automod_rule.dart';
import '../domain/composer_draft.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/chat_models.dart';
import '../domain/expression_favorites.dart';
import '../domain/chat_repository.dart';
import '../domain/discord_permissions.dart';
import '../domain/navigation_memory.dart';
import '../domain/discord_snowflake.dart';
import '../domain/forum_repository.dart';
import '../domain/guild_management.dart';
import '../domain/guild_expression_repository.dart';
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
import '../domain/user_notes.dart';
import '../domain/user_profile.dart';
import '../domain/user_settings_repository.dart';
import '../domain/voice_call.dart';
import '../domain/voice_connection.dart';
import '../domain/voice_message_recorder.dart';
import '../domain/voice_message_repository.dart';
import '../domain/workspace_permissions.dart';
import 'channel_activity_persistence.dart';
import '../app_log.dart';

part 'chat_controller_events.dart';
part 'chat_controller_typing.dart';
part 'chat_controller_presence.dart';
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
part 'chat_controller_guild_access.dart';
part 'chat_controller_read_state.dart';
part 'chat_controller_history_window.dart';

enum ChatLoadState { idle, loading, ready, failure }

final class ChatController extends ChangeNotifier {
  /// [landingChannelIn] names the channel the app opens on when a workspace
  /// first loads. Without it the app opens on the first text channel.
  /// [readingPositions] says where the reader stopped in each channel, so that
  /// opening a channel can load that stretch of it.
  ChatController(
    ChatRepository repository, {
    String? Function(ChatWorkspace workspace)? landingChannelIn,
    ReadingPositions? readingPositions,
  }) : _repository = repository,
       _landingChannelIn = landingChannelIn,
       _readingPositions = readingPositions {
    _listenToRepository();
  }

  final String? Function(ChatWorkspace workspace)? _landingChannelIn;
  final ReadingPositions? _readingPositions;
  ChatRepository _repository;

  /// Set once [_repository] has begun to close, so that it closes only once.
  Future<void>? _repositoryClosed;
  StreamSubscription<ChatRepositoryEvent>? _eventSubscription;
  StreamSubscription<ReadStateSnapshot>? _readStateSubscription;
  StreamSubscription<String>? _conversationSummarySubscription;
  final StreamController<MessageUpsertedEvent> _incomingMessages =
      StreamController.broadcast();

  ChatLoadState _state = ChatLoadState.idle;
  ChatWorkspace? _workspace;
  Object? _error;

  /// Channels with a send on its way. Each channel takes one send at a time,
  /// and a slow one does not hold the others.
  final Set<String> _sendingChannels = {};
  RepositoryConnectionStatus _connectionStatus =
      RepositoryConnectionStatus.offline;
  final Set<String> _loadedChannels = {};

  /// Held channels that may lack messages since a [HistoryGapEvent]. A page from
  /// Discord clears a channel, and a page from the cache does not.
  final Set<String> _channelsWithGap = {};

  /// Per channel catching up, the messages that came live since its page was
  /// asked for. The page may lack them, and they stay when it lands.
  final Map<String, Set<String>> _catchingUpChannels = {};

  /// Channels showing a locally held page while their refresh is in flight.
  /// A refresh that then fails leaves what is on screen rather than an error.
  final Set<String> _restoredChannels = {};
  final Set<String> _loadingChannels = {};
  final Map<String, Object> _channelErrors = {};
  final Set<String> _loadingOlderChannels = {};
  final Set<String> _exhaustedChannels = {};
  final Map<String, Object> _olderChannelErrors = {};

  final _windows = _HistoryWindows();
  final Map<String, ChannelHistory> _pinnedMessages = {};
  final Set<String> _loadingPins = {};
  final Map<String, Object> _pinErrors = {};
  final Map<String, List<GuildScheduledEvent>> _scheduledEventsBySpace = {};
  final Map<String, List<GuildScheduledEventAttendee>> _eventAttendees = {};
  final Set<String> _loadingEventAttendees = {};
  final Set<String> _loadingScheduledEventSpaces = {};
  final Map<String, Object> _scheduledEventErrors = {};
  final Map<String, DateTime> _lastSentAt = {};
  ComposerDraftStore _drafts = MemoryComposerDraftStore();
  final Map<String, Set<String>> _typingMembers = {};
  final Map<String, Timer> _typingTimers = {};
  final Map<String, DateTime> _typingRequests = {};
  final Map<String, UserPresence> _heldPresences = {};
  Timer? _presenceFold;
  final _typingSignal = _TypingSignal();
  final _archivedThreadState = _ArchivedThreadState();

  /// Per space, the authors a member request has already asked about.
  final Map<String, Set<String>> _askedAuthors = {};
  String? _activeChannelId;
  String? _guildAccessError;

  /// Invite previews asked for by messages, per code, for this session.
  final Map<String, Future<InvitePreview>> _invitePreviews = {};
  bool _isApplicationActive = true;
  ChatMessage? _lastSentMessage;

  /// Set while the window is away. The first message to arrive in the active
  /// channel then replaces its unread boundary.
  bool _boundaryAwaitsNewMessage = false;

  /// The read state of each channel that opened unread and is still loading, as
  /// it stood before the open acked it. Its history names the first unread
  /// message, so the boundary can only be set when a page arrives.
  final Map<String, ReadState> _unreadOpenings = {};
  bool _disposed = false;

  ChatLoadState get state => _state;
  ChatWorkspace? get workspace => _workspace;
  Object? get error => _error;
  bool isSendingIn(String channelId) => _sendingChannels.contains(channelId);
  RepositoryConnectionStatus get connectionStatus => _connectionStatus;
  String? get activeChannelId => _activeChannelId;

  /// Whether the window has the user's attention, as the platform sees it.
  ///
  /// The same fact the read-state acknowledgement reads: an incoming message
  /// that lands while this is true, in the channel being looked at, is one the
  /// user is already seeing.
  bool get isApplicationActive => _isApplicationActive;

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

  /// The games the active transport can name as a game, when it has one.
  DetectableGameRepository? get detectableGames => _repository.detectableGames;

  /// The lazy member-list surface, when the active transport offers one.
  ///
  /// Only the desktop-user transport can serve rosters; every other transport
  /// reports `null` so the member panel falls back to what the workspace
  /// already knows rather than waiting for rows that will never arrive.
  /// Asks a guild about members matching [query].
  ///
  /// Fire-and-forget: Discord answers on the gateway and the reply arrives as
  /// an ordinary member update, which is what refreshes anything showing them.
  void searchGuildMembers({required String spaceId, required String query}) {
    if (spaceId.isEmpty || query.trim().isEmpty) return;
    memberListRepository?.searchGuildMembers(
      guildId: spaceId,
      query: query.trim(),
    );
  }

  /// Asks about the people a history page names, authors and mentions alike,
  /// whose standing in the guild is not known yet. A page says nothing of it,
  /// and the nickname and the name's colour come from it. Each person is
  /// asked about once per session, so moving between channels sends nothing
  /// new.
  void _askAboutAuthors(ChannelHistory history) {
    final workspace = _workspace;
    final channel = workspace?.channelOrNull(history.channelId);
    if (workspace == null || channel == null || channel.isDirectMessage) return;
    final spaceId = channel.spaceId;
    final asked = _askedAuthors.putIfAbsent(spaceId, () => {});
    final named = {
      for (final message in history.messages) ...[
        message.authorId,
        ...message.mentionedMemberIds,
      ],
    };
    final unknown = [
      for (final id in named)
        if (workspace.memberOrNull(id)?.membershipIn(spaceId) == null &&
            asked.add(id))
          id,
    ];
    if (unknown.isEmpty) return;
    memberListRepository?.requestGuildMembers(
      guildId: spaceId,
      userIds: unknown,
    );
  }

  GuildMemberListRepository? get memberListRepository {
    final repository = _repository;
    return repository is GuildMemberListRepository
        ? repository as GuildMemberListRepository
        : null;
  }

  /// The id of the message this client last sent, if it went to [channelId].
  String? lastSentMessageIdIn(String channelId) =>
      _lastSentMessage?.channelId == channelId ? _lastSentMessage?.id : null;

  void setApplicationActive(bool value) {
    if (_isApplicationActive == value) return;
    _isApplicationActive = value;
    _boundaryAwaitsNewMessage = !value;
    if (!value && _activeChannelId != null) {
      // The NEW line stays on screen, since leaving the window must move
      // nothing. The saved copy drops it, so a later launch does not open on it.
      unawaited(
        ChannelActivityPersistence.save(
          _repository,
          _workspace?.clearChannelUnreadBoundary(_activeChannelId!),
          _activeChannelId!,
        ),
      );
    }
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

  /// When this account's last message in the channel went out. Slowmode's
  /// clock starts here, per channel, so moving between channels cannot reset it.
  DateTime? lastSentAt(String channelId) => _lastSentAt[channelId];

  /// What this account has written and not sent, per channel.
  ComposerDraftStore get drafts => _drafts;
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

  /// Closes the session before the process ends, so that what it still holds
  /// reaches the disk and the server. A socket that does not answer must not
  /// hold the exit, so the wait is short. The cache is the first thing a
  /// repository saves when it closes, so this wait does not put it at risk.
  Future<void> closeForExit() =>
      _closeRepository().timeout(const Duration(seconds: 2), onTimeout: () {});

  Future<void> _closeRepository() => _repositoryClosed ??= _repository.close();

  Future<void> useRepository(ChatRepository repository) async {
    await _eventSubscription?.cancel();
    await _readStateSubscription?.cancel();
    await _conversationSummarySubscription?.cancel();
    await _closeRepository();
    _repository = repository;
    _repositoryClosed = null;
    _workspace = null;
    _loadedChannels.clear();
    _channelsWithGap.clear();
    _catchingUpChannels.clear();
    _restoredChannels.clear();
    _loadingChannels.clear();
    _channelErrors.clear();
    _loadingOlderChannels.clear();
    _exhaustedChannels.clear();
    _olderChannelErrors.clear();
    _windows.clear();
    _pinnedMessages.clear();
    _loadingPins.clear();
    _pinErrors.clear();
    _scheduledEventsBySpace.clear();
    _eventAttendees.clear();
    _loadingEventAttendees.clear();
    _loadingScheduledEventSpaces.clear();
    _scheduledEventErrors.clear();
    _lastSentAt.clear();
    // A new store, not a cleared one: a composer closing now, or a send failing
    // late, still writes to the store of the account it belongs to.
    _drafts = MemoryComposerDraftStore();
    _archivedThreadState.clear();
    _askedAuthors.clear();
    _invitePreviews.clear();
    _clearTyping();
    // Presences still held belong to the last account.
    _presenceFold?.cancel();
    _presenceFold = null;
    _heldPresences.clear();
    _unreadOpenings.clear();
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
    if (_state == ChatLoadState.ready) {
      // The read state came back whole with the workspace, so this is the one
      // moment a session can judge which entries are older than the collector
      // keeps. A transport without read state has nothing to collect.
      unawaited(collectReadStateGarbage());
      // READY's own update reached the controller before it had a workspace to
      // fold it into, and the first screen must already show it.
      _applyReadState();
    }
    notifyListeners();
    final workspace = _workspace;
    // A link held through the launch has opened its channel during the notify
    // above. The user asked for that channel, so the app does not land elsewhere.
    if (_state == ChatLoadState.ready &&
        workspace != null &&
        _activeChannelId == null) {
      final landing = _landingChannelIn;
      final channelId = landing == null
          ? _firstTextChannelIn(workspace)
          : landing(workspace);
      if (channelId != null) unawaited(openChannel(channelId));
    }
  }

  /// A voice channel does carry messages, but it is never the channel the app
  /// lands on unasked, so warming its history here would be wasted work.
  String? _firstTextChannelIn(ChatWorkspace workspace) {
    final permissions = WorkspacePermissions(workspace);
    return workspace.channels
        .where(
          (channel) =>
              channel.kind != ChannelKind.voice &&
              !channel.isThread &&
              permissions.can(DiscordPermissions.viewChannel, channel),
        )
        .firstOrNull
        ?.id;
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
    if (previousChannelId != null) _capChannelIfNotOpen(previousChannelId);
    // Read here, because the ack below moves the cursor.
    final stateAtOpen = readState.forChannel(channelId);
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
    final workspace = _workspace;
    if (workspace == null) {
      notifyListeners();
      return;
    }
    if (_loadedChannels.contains(channelId) && !refresh) {
      if (anchorMessageId == null) {
        // Coming back to a channel left in an old window opens on the present,
        // unless the reader scrolled there and so has a place in it to return
        // to. Tapping the channel already open leaves the reader in place.
        if (hasNewerMessages(channelId) &&
            previousChannelId != channelId &&
            !_holdsReadingPosition(channelId)) {
          await jumpToPresent(channelId);
        } else {
          unawaited(_catchUpChannel(channelId));
          notifyListeners();
        }
        await _returnToReadingPosition(channelId);
      } else if (workspace
          .messagesFor(channelId)
          .any((message) => message.id == anchorMessageId)) {
        // A window still on its way would take the reader off this message.
        _windows.begin(channelId);
        notifyListeners();
      } else {
        await _moveWindow(channelId, aroundMessageId: anchorMessageId);
      }
      return;
    }
    // A jump does not wait for a plain load in flight, whose page may not hold
    // the message. It takes the load's place.
    if (_loadingChannels.contains(channelId) && anchorMessageId == null) {
      notifyListeners();
      return;
    }
    final isCurrent = _windows.begin(channelId);
    _loadingChannels.add(channelId);
    _channelErrors.remove(channelId);
    _olderChannelErrors.remove(channelId);
    // A link that names a message opens on that message. Its page is a window
    // around the anchor, which says nothing about where unread starts.
    if (anchorMessageId == null &&
        stateAtOpen != null &&
        stateAtOpen.isBehind(channel?.lastMessageId)) {
      _unreadOpenings[channelId] = stateAtOpen;
    }
    notifyListeners();
    try {
      // A link that names a message lands on that message: the window is
      // asked for around the anchor, which reaches history the client holds
      // no page of. The plain open still reads forward from the end.
      final page = await _repository.loadChannelHistory(
        channelId,
        aroundMessageId: anchorMessageId,
      );
      if (!isCurrent()) return;
      _applyWindow(channelId, page, aroundMessageId: anchorMessageId);
      final reached =
          anchorMessageId == null &&
          await _reachReadingPosition(channelId, isCurrent);
      if (!reached) await _reachFirstUnread(channelId, page, isCurrent);
      if (!isCurrent()) return;
      _setBoundaryOfUnreadOpening(channelId);
      _loadedChannels.add(channelId);
      if (anchorMessageId == null && !page.fromCache) {
        _channelsWithGap.remove(channelId);
      }
      // The page may name a newer message than the channel record did, and the
      // channel is on screen either way, so the cursor is moved again here.
      acknowledgeChannel(channelId);
    } catch (error) {
      // A channel already reading from its local copy keeps it. The error
      // state is for a channel with nothing to show.
      if (isCurrent() && !_restoredChannels.contains(channelId)) {
        _channelErrors[channelId] = error;
      }
    } finally {
      if (isCurrent()) {
        _unreadOpenings.remove(channelId);
        _loadingChannels.remove(channelId);
      }
      _capChannelIfNotOpen(channelId);
      if (!_disposed) notifyListeners();
    }
  }

  /// Keeps a channel the reader is not in under the cap. A channel that lost
  /// messages counts as not loaded, so opening it fetches its history again.
  void _capChannelIfNotOpen(String channelId) {
    if (channelId == _activeChannelId) return;
    final capped = _workspace?.capChannel(channelId);
    if (identical(capped, _workspace)) return;
    _workspace = capped;
    _loadedChannels.remove(channelId);
  }

  /// Sets the boundary of [channelId] if it opened unread. Answers whether the
  /// list can open now: false when the channel opened unread and no held message
  /// is unread yet, so opening would land on the wrong place.
  bool _setBoundaryOfUnreadOpening(String channelId) {
    final opening = _unreadOpenings[channelId];
    if (opening == null) return true;
    _workspace = _workspace?.withUnreadBoundaryFrom(opening);
    return _workspace?.channelOrNull(channelId)?.firstUnreadMessageId != null;
  }

  Future<String?> openDirectConversation(String recipientId) async {
    final value = recipientId.trim();
    if (value.isEmpty || _workspace == null) return null;
    try {
      final conversation = await _repository.openDirectConversation(value);
      _workspace = conversation.recipients
          .fold(
            _workspace!.upsertSpace(const CommunitySpace.directMessages()),
            (workspace, recipient) => workspace.upsertMember(recipient),
          )
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
    final isCurrent = _windows.current(channelId);
    try {
      final page = await _repository.loadChannelHistory(
        channelId,
        beforeMessageId: messages.first.id,
      );
      // This page sits next to a window that has since been replaced.
      if (!isCurrent()) return;
      _workspace = _workspace?.mergeHistory(
        page.history,
        replaceChannel: false,
      );
      _askAboutAuthors(page.history);
      _setHistoryExhausted(
        channelId,
        !page.hasMore || page.history.messages.isEmpty,
      );
    } catch (error) {
      _olderChannelErrors[channelId] = error;
    } finally {
      _loadingOlderChannels.remove(channelId);
      _capChannelIfNotOpen(channelId);
      if (!_disposed) notifyListeners();
    }
  }

  /// Puts a transport's locally held page on screen while its refresh runs.
  ///
  /// The channel counts as loaded from here: it has messages to read, so the
  /// loading view would only hide them. The one exception is below.
  /// Answers whether the channel took the restored page.
  bool _restoreChannelHistory(ChannelHistoryRestoredEvent event) {
    final channelId = event.history.channelId;
    if (_workspace == null || _loadedChannels.contains(channelId)) return false;
    _workspace = _workspace?.mergeInitialHistory(event.history);
    _loadedChannels.add(channelId);
    _restoredChannels.add(channelId);
    // The list reads the boundary once, when it opens, so a channel with no
    // boundary yet waits for the refresh that can name one.
    if (_setBoundaryOfUnreadOpening(channelId)) {
      _loadingChannels.remove(channelId);
    }
    _setHistoryExhausted(channelId, !event.hasMore);
    return true;
  }

  /// Answers a stretch with no live events.
  ///
  /// The active channel fetches at once. Other held channels stop counting as
  /// loaded, so opening one fetches, the same way a first open does. All of them
  /// count as restored: what they hold stays readable if that fetch fails.
  void _acceptHistoryGap() {
    final activeId = _activeChannelId;
    _channelsWithGap.addAll(_loadedChannels);
    _restoredChannels.addAll(_loadedChannels);
    _loadedChannels.removeWhere((id) => id != activeId);
    if (activeId != null) unawaited(_catchUpChannel(activeId));
  }

  /// Fetches the newest page of a channel on screen that has a gap.
  ///
  /// It stays in view during the fetch, because a loading view would throw away
  /// the reader's place in it. A failed fetch leaves the gap, and opening the
  /// channel again retries. An old window keeps its gap too: leaving it loads the
  /// newest page anyway, and a jump made during the fetch keeps its window.
  Future<void> _catchUpChannel(String channelId) async {
    if (!_channelsWithGap.contains(channelId) ||
        hasNewerMessages(channelId) ||
        _catchingUpChannels.containsKey(channelId)) {
      return;
    }
    final arrived = _catchingUpChannels[channelId] = {};
    final isCurrent = _windows.current(channelId);
    try {
      final page = await _repository.loadChannelHistory(channelId);
      if (page.fromCache ||
          _workspace?.channelOrNull(channelId) == null ||
          !isCurrent()) {
        return;
      }
      _workspace = _workspace?.catchUpHistory(page.history, arrived: arrived);
      _channelsWithGap.remove(channelId);
      _setHistoryExhausted(channelId, !page.hasMore);
      // The window may be away: then the missed messages stay unread.
      if (_isApplicationActive && channelId == _activeChannelId) {
        acknowledgeChannel(channelId);
      }
    } catch (error) {
      AppLog.warning(
        'chat',
        'Could not load messages missed in a reconnect: $error',
        error: error,
      );
    } finally {
      _catchingUpChannels.remove(channelId);
      _capChannelIfNotOpen(channelId);
      if (!_disposed) notifyListeners();
    }
  }

  /// Takes a channel out of the workspace, with what the controller knew about
  /// its history. It holds no messages now, so if it comes back it has to load.
  void _removeChannel(String channelId) {
    _workspace = _workspace?.removeChannel(channelId);
    _forgetChannelHistory(channelId);
  }

  /// The same as [_removeChannel] for a guild and all its channels.
  void _removeGuild(String spaceId) {
    final workspace = _workspace;
    if (workspace == null) return;
    for (final channel in workspace.channels) {
      if (channel.spaceId == spaceId) _forgetChannelHistory(channel.id);
    }
    _workspace = workspace.removeGuild(spaceId);
  }

  /// Folds a whole READY's changes in. A channel that goes loses its history
  /// state, as with [_removeChannel] and [_removeGuild].
  void _applyWorkspaceDiff(WorkspaceDiff diff) {
    final workspace = _workspace;
    if (workspace == null) return;
    for (final channel in workspace.channels) {
      if (diff.removes(channel)) _forgetChannelHistory(channel.id);
    }
    _workspace = workspace.applyDiff(diff);
  }

  void _forgetChannelHistory(String channelId) {
    _loadedChannels.remove(channelId);
    _channelsWithGap.remove(channelId);
    _restoredChannels.remove(channelId);
    _exhaustedChannels.remove(channelId);
    _channelErrors.remove(channelId);
    _olderChannelErrors.remove(channelId);
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
    // A refusal below must not be read as the failure of some earlier action.
    _error = null;
    final workspace = _workspace;
    final spoken = _spokenCommandFrom(body.trim());
    final content = spoken.$2;
    if (workspace == null || (content.isEmpty && attachments.isEmpty)) {
      return false;
    }
    return _sendingIn(channelId, () async {
      final message = await _repository.sendMessage(
        channelId: channelId,
        authorId: workspace.currentMemberId,
        body: content,
        attachments: attachments,
        replyToMessageId: replyToMessageId,
        suppressNotifications: suppressNotifications,
        textToSpeech: spoken.$1,
      );
      _applySentMessage(message);
    });
  }

  /// The spoken-aloud command: `/tts <message>` sends the message flagged to
  /// be read aloud, without the command in the text.
  ///
  /// The account's own setting gates it, and an account that turned it off
  /// types a literal slash message like any other text. The command needs an
  /// argument, so a bare `/tts` is not one either.
  (bool, String) _spokenCommandFrom(String content) {
    if (!allowsTextToSpeech || !content.startsWith('/tts ')) {
      return (false, content);
    }
    return (true, content.substring('/tts '.length).trim());
  }

  Future<bool> editMessage(ChatMessage message, String body) async {
    final content = body.trim();
    if (!message.canEdit || content.isEmpty) return false;
    return _sendingIn(message.channelId, () async {
      final updated = await _repository.editMessage(
        channelId: message.channelId,
        messageId: message.id,
        body: content,
      );
      _workspace = _workspace?.upsertMessage(updated);
    });
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

  /// Folds in a message this client just sent. It reads its channel, and the
  /// timeline takes the reader to it.
  void _applySentMessage(ChatMessage message) {
    final channelId = message.channelId;
    if (hasNewerMessages(channelId)) unawaited(jumpToPresent(channelId));
    if (!_keepOutOfOldWindow(message)) {
      _workspace = _workspace?.upsertMessage(message);
    }
    _workspace = _workspace?.clearChannelUnreadBoundary(channelId);
    _persistChannelActivity(channelId);
    _lastSentMessage = message;
    _catchingUpChannels[channelId]?.add(message.id);
    // Slowmode counts every kind of message, so every send starts its clock.
    _lastSentAt[channelId] = DateTime.now();
  }

  /// Runs [send] as the one send of [channelId], with its composer busy until
  /// it ends. Returns false when the channel already has a send on its way, or
  /// when [send] throws, and then [error] holds why.
  Future<bool> _sendingIn(
    String channelId,
    Future<void> Function() send,
  ) async {
    if (!_sendingChannels.add(channelId)) return false;
    notifyListeners();
    try {
      await send();
      _error = null;
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _sendingChannels.remove(channelId);
      notifyListeners();
    }
  }

  void _persistChannelActivity(String channelId) => unawaited(
    ChannelActivityPersistence.save(_repository, _workspace, channelId),
  );

  void _notify() => notifyListeners();

  @override
  void dispose() {
    _disposed = true;
    _presenceFold?.cancel();
    _clearTyping();
    _typingSignal.dispose();
    unawaited(_readStateSubscription?.cancel());
    unawaited(_eventSubscription?.cancel());
    unawaited(_conversationSummarySubscription?.cancel());
    unawaited(_closeRepository());
    unawaited(_incomingMessages.close());
    super.dispose();
  }
}
