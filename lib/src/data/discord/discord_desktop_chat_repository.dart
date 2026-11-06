import '../../domain/desktop_relationship_repository.dart';
import '../../domain/scheduled_event_repository.dart';
import '../../domain/sticker_repository.dart';
import '../../domain/age_verification.dart';
import '../../domain/multi_factor_auth.dart';
import '../../domain/auth_session.dart';
import '../../domain/family_centre.dart';
import '../../domain/account_standing.dart';
import '../../domain/account_connections.dart';
import '../../domain/account_data_package.dart';
import '../../domain/account_entitlements.dart';
import '../../domain/app_authorisation.dart';

import '../../domain/automod_rule.dart';
import 'dart:async';

import 'package:collection/collection.dart' show SetEquality;

import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/expression_favorites.dart';
import '../../domain/chat_repository.dart';
import '../../domain/guild_expression_repository.dart';
import '../../domain/game_detection.dart';
import '../../domain/guild_management_repository.dart';
import '../../domain/guild_member_list.dart';
import '../../domain/guild_membership.dart';
import '../../domain/guild_member_list_repository.dart';
import '../../domain/message_flag_repository.dart';
import '../../domain/message_forward_repository.dart';
import '../../domain/message_search_repository.dart';
import '../../domain/moderation_repository.dart';
import '../../domain/permission_overwrite.dart';
import '../../domain/presence_repository.dart';
import '../../domain/reaction_repository.dart';
import '../../domain/read_state_repository.dart';
import '../../domain/user_settings_repository.dart';
import '../../domain/voice_call.dart';
import '../../domain/application_command.dart';
import '../../domain/conversation_summary.dart';
import '../../domain/go_live_stream.dart';
import '../../domain/message_component.dart';
import '../../domain/gif_picker.dart';
import '../../domain/soundboard.dart';
import '../../domain/stage_channel.dart';
import '../../domain/forum_repository.dart';
import '../../domain/thread_membership.dart';
import '../../domain/thread_repository.dart';
import '../../domain/user_profile.dart';
import '../../domain/user_notes.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import '../../domain/voice_message_recorder.dart';
import '../../domain/voice_message_repository.dart';
import 'discord_desktop_api_client.dart';
import 'discord_read_state_repository.dart';
import 'discord_detectable_game_service.dart';
import 'discord_direct_messages.dart';
import 'discord_repository_events.dart';
import 'discord_user_settings_repository.dart';
import 'discord_desktop_gateway_client.dart';
import 'discord_direct_call_service.dart';
import 'discord_gateway_client.dart';
import 'discord_guild_admin_mapper.dart';
import 'discord_mapper.dart';
import 'discord_member_list_handler.dart';
import 'discord_message_search_service.dart';
import 'discord_message_nonce_factory.dart';
import 'discord_presence_service.dart';
import 'discord_rest_client.dart';
import 'discord_shared_dispatches.dart';
import 'discord_user_notes_repository.dart';
import 'discord_user_profile_repository.dart';
import 'discord_application_command_service.dart';
import 'discord_conversation_summary_service.dart';
import 'discord_desktop_relationships.dart';
import 'discord_relationship_service.dart';
import 'discord_go_live_service.dart';
import 'discord_message_component_service.dart';
import 'discord_expression_favorites_repository.dart';
import 'discord_expression_service.dart';
import 'discord_gif_service.dart';
import 'discord_soundboard_service.dart';
import 'discord_stage_service.dart';
import 'discord_thread_directory.dart';
import 'discord_thread_membership_service.dart';
import 'discord_voice_signaling_service.dart';
import 'discord_voice_socket_factory.dart';
import '../../app_log.dart';

import 'discord_account_cache.dart';
import 'discord_restored_history.dart';

part 'discord_desktop_chat_events.dart';
part 'discord_desktop_chat_session.dart';

final class DiscordDesktopChatRepository
    implements
        ChatRepository,
        ThreadListRepository,
        ForumPostRepository,
        GuildMemberListRepository,
        ScheduledEventRepository,
        VoiceMessageRepository,
        MessageForwardRepository,
        StickerRepository,
        MessageFlagRepository,
        ReactionRepository,
        SuperReactionRepository {
  DiscordDesktopChatRepository(
    this._api,
    this._gateway,
    this._cache, {
    String? accountId,
    DiscordMapper? mapper,
    DiscordMessageNonceFactory? nonceFactory,
    VoiceDaveService? daveService,
    Future<void> Function()? clearChatImages,
  }) : _accountId = accountId,
       _clearChatImages = clearChatImages,
       _mapper = mapper ?? DiscordMapper(),
       _nonceFactory = nonceFactory ?? DiscordMessageNonceFactory(),
       _userSettings = DiscordUserSettingsRepository(_api),
       _readState = DiscordReadStateRepository(_api),
       _threadMembership = DiscordThreadMembershipService(_api),
       _stages = DiscordStageService(_api),
       _soundboard = DiscordSoundboardService(_api),
       _gifs = DiscordGifService(_api),
       _favorites = DiscordExpressionFavoritesRepository(_api),
       _applicationCommands = DiscordApplicationCommandService(
         _api,
         sessionId: () => _gateway.sessionId,
       ),
       _messageComponents = DiscordMessageComponentService(
         _api,
         sessionId: () => _gateway.sessionId,
       ),

       _voiceSignaling = DiscordVoiceSignalingService(
         mainGateway: _gateway,
         socketFactory: DiscordVoiceGatewaySocketFactory(
           daveService: daveService,
         ),
         callGateway: _gateway,
       ) {
    _memberLists = DiscordMemberListHandler(_mapper);
    _messageSearch = DiscordMessageSearchService(
      requester: _api.searchMessages,
      mapper: _mapper,
    );
    _presence = DiscordPresenceService(
      sendPresence: _gateway.updatePresence,
      isSessionEstablished: () => _gateway.isSessionEstablished,
      settings: _userSettings,
    );
    // The account's own row is composed locally, so it has to be republished
    // whenever the composition changes: R07 is explicit that no server frame
    // will ever supply it.
    _selfPresenceSubscription = _presence.selfPresenceUpdates.listen(
      (_) => _emitSelfPresence(),
    );
    _directCalls = DiscordDirectCallService(
      api: _api,
      gateway: _gateway,
      signaling: _voiceSignaling,
      events: _gateway.events,
    );
    _gatewaySubscription = _gateway.events.listen(_acceptGatewayEvent);
    // A guild the account joins or creates mid-session must land in the cache
    // and start receiving live events, exactly as the guilds READY listed.
    final access = _api.guildManagement;
    access.onGuildGained = _persistGainedGuild;
    access.onGuildLeft = _persistLeftGuild;
    // R03: a re-IDENTIFY may echo the cache versions the last READY carried,
    // so the socket asks the read-state store for them at the moment it needs
    // them rather than being handed a snapshot that is stale by then.
    _gateway.useClientStateProvider(_readState.identifyClientState);
  }

  static const _pageSize = 100;

  final DiscordDesktopApiClient _api;
  final DiscordDesktopGatewayClient _gateway;
  final ChatCache _cache;
  final DiscordMapper _mapper;
  final DiscordMessageNonceFactory _nonceFactory;
  final DiscordUserSettingsRepository _userSettings;
  final DiscordReadStateRepository _readState;
  final DiscordVoiceSignalingService _voiceSignaling;
  final DiscordThreadMembershipService _threadMembership;
  late final DiscordThreadDirectory _threads = DiscordThreadDirectory(
    routes: _api.threads,
    cache: _cache,
    mapper: _mapper,
    currentMemberId: () => _currentMemberId,
    // A search lists this account's own membership of each thread it joined.
    onSelfMember: (member) =>
        _threadMembership.accept('THREAD_MEMBER_UPDATE', member),
  );
  final DiscordStageService _stages;
  final DiscordSoundboardService _soundboard;
  final DiscordExpressionFavoritesRepository _favorites;
  final DiscordGifService _gifs;
  final DiscordApplicationCommandService _applicationCommands;
  final DiscordMessageComponentService _messageComponents;
  // Built after construction because the adapter reads the signed-in account
  // off this repository, which does not exist yet in the initialiser list.
  final DiscordRelationshipService _relationships =
      DiscordRelationshipService();
  final DiscordConversationSummaryService _summaries =
      DiscordConversationSummaryService();
  late final DiscordGoLiveService _goLive = DiscordGoLiveService(_gateway);
  late final DiscordUserProfileRepository _userProfile =
      DiscordUserProfileRepository(_api);
  late final DiscordUserNotesRepository _userNotes = DiscordUserNotesRepository(
    _api,
  );
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();
  late final StreamSubscription<DiscordGatewayEvent> _gatewaySubscription;
  late final DiscordMemberListHandler _memberLists;
  late final DiscordMessageSearchService _messageSearch;
  late final DiscordPresenceService _presence;
  late final DetectableGameRepository _detectableGames =
      DiscordDetectableGameService(_api);
  late final DiscordDirectCallService _directCalls;
  late final StreamSubscription<SelfPresence> _selfPresenceSubscription;
  String? _currentMemberId;
  late final DiscordDirectMessages _directMessages = DiscordDirectMessages(
    _api.createDirectMessageChannel,
    _cache,
    _mapper,
    _events.publish,
    onChannelAdded: _readState.addPrivateChannel,
  );
  late final DiscordSharedDispatches _sharedDispatches =
      DiscordSharedDispatches(
        cache: _cache,
        mapper: _mapper,
        directMessages: _directMessages,
        currentMemberId: () => _currentMemberId,
        updatedMessage: (payload, held) =>
            _messageFrom(payload, fallback: held),
        events: _events,
      );

  /// Who the session's credential says it is, before Discord has confirmed it.
  /// The offline fallback compares this with the account of the cache.
  final String? _accountId;

  /// Removes the pictures of the chats from disk, when another account's
  /// cache is found. Null where the app keeps no pictures on disk.
  final Future<void> Function()? _clearChatImages;

  /// Whether a workspace is being shown, live or from the cache.
  ///
  /// A READY that arrives before this is the first hydration and is answered
  /// by [loadWorkspace]; one that arrives after is a reconnect's fresh view
  /// and is answered by the in-place rehydration instead.
  bool _workspaceShown = false;

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  /// The desktop-user session carries voice on the very socket it already uses
  /// for messages, so the service is offered unconditionally. Whether a join
  /// can actually complete is the service's own call — it refuses before the
  /// gateway is ready or without DAVE — and it reports that as a failure event
  /// the voice surface can show, which a null here could not.
  @override
  VoiceSignalingService? get voiceSignaling => _voiceSignaling;

  /// The desktop-user session is authenticated as the account itself, so it is
  /// the only transport that can read or edit that account's profile.
  @override
  UserProfileRepository? get userProfile => _userProfile;

  /// Notes are account state on the user's own session: `READY` carries the
  /// whole map, this socket receives every later revision of it, and these
  /// credentials are the only ones allowed to write one of its entries.
  @override
  UserNotesRepository? get userNotes => _userNotes;

  @override
  ThreadMembershipRepository? get threadMembership => _threadMembership;

  @override
  StageRepository? get stages => _stages;

  @override
  SoundboardRepository? get soundboard => _soundboard;

  /// Upload and delete for the guild's emoji, stickers and sounds, sharing
  /// the session's credentials and the soundboard store so a sound uploaded
  /// here is in the picker the moment the answer arrives.
  @override
  GuildExpressionRepository? get expressions => _expressions;

  late final DiscordExpressionService _expressions = DiscordExpressionService(
    _api,
    _cache,
    _mapper,
    soundboard: _soundboard,
    // The settings window's own writes reach the picker through the same
    // event the gateway's emoji and sticker updates do.
    publish: (event) {
      if (!_events.isClosed) _events.add(event);
    },
  );

  @override
  GifRepository? get gifs => _gifs;

  @override
  ExpressionFavoritesRepository? get expressionFavorites => _favorites;

  @override
  MessageComponentRepository? get messageComponents => _messageComponents;

  @override
  GoLiveRepository? get goLive => _goLive;

  @override
  ConversationSummaryRepository? get conversationSummaries => _summaries;

  @override
  ApplicationCommandRepository? get applicationCommands => _applicationCommands;

  /// The desktop-user session is the only transport holding the account's
  /// settings blob: `READY` delivers it on this very socket.
  @override
  UserSettingsRepository? get userSettings => _userSettings;

  /// Read state is account state on the user's own session: `READY` carries
  /// it, this socket receives every later revision of it, and these
  /// credentials are the only ones allowed to acknowledge one.
  @override
  ReadStateRepository? get readState => _readState;

  /// The desktop-user session owns both halves a call needs — the gateway
  /// socket for opcode 13 and the user's REST credentials for the ring routes —
  /// so it is the one transport that can offer this.
  @override
  DirectCallService? get directCalls => _directCalls;

  /// The desktop-user session is the transport Discord's own settings window
  /// runs on, and the only one here holding a member whose permissions the
  /// surface can be gated by.
  @override
  GuildManagementRepository? get guildManagement => _api.guildManagement;

  @override
  ModerationRepository? get moderation => _api.moderation;

  @override
  SafetyHubRepository? get safetyHub => _api.safetyHub;

  @override
  FamilyCentreRepository? get familyCentre => _api.familyCentre;

  @override
  AuthSessionRepository? get authSessions => _api.authSessions;

  @override
  MultiFactorAuthRepository? get multiFactorAuth => _api.multiFactorAuth;

  @override
  AgeVerificationRepository? get ageVerification => _api.ageVerification;

  @override
  AccountConnectionsRepository? get accountConnections =>
      _api.accountConnections;

  @override
  AccountEntitlementsRepository? get accountEntitlements =>
      _api.accountEntitlements;

  @override
  AppAuthorisationRepository? get appAuthorisation => _api.appAuthorisation;

  @override
  AccountDataPackageRepository? get accountDataPackage =>
      _api.accountDataPackage;

  @override
  DesktopRelationshipRepository? get relationships => _relationshipView;

  late final DiscordDesktopRelationships _relationshipView =
      DiscordDesktopRelationships(_relationships, _api);

  /// The account's own session is what Discord's search routes answer to, so
  /// this is the one transport that can offer them.
  @override
  MessageSearchRepository? get messageSearch => _messageSearch;

  /// The desktop-user session is the only transport that can broadcast a
  /// status: opcode 3 rides its socket and the custom status lives in the
  /// settings blob it alone can read.
  @override
  PresenceService? get presence => _presence;

  @override
  DetectableGameRepository? get detectableGames => _detectableGames;

  @override
  Stream<GuildMemberList> get memberListUpdates => _memberLists.updates;

  @override
  String memberListIdFor({
    required String guildId,
    required String channelId,
  }) => _memberLists.memberListIdFor(guildId: guildId, channelId: channelId);

  @override
  GuildMemberList? memberListFor({
    required String guildId,
    required String listId,
  }) => _memberLists.listFor(guildId: guildId, listId: listId);

  @override
  void subscribeMemberRanges({
    required String guildId,
    required String channelId,
    required List<List<int>> ranges,
  }) => _gateway.subscribeMemberRanges(
    guildId: guildId,
    channelId: channelId,
    ranges: ranges,
  );

  @override
  void unsubscribeMemberRanges({
    required String guildId,
    required String channelId,
  }) =>
      _gateway.unsubscribeMemberRanges(guildId: guildId, channelId: channelId);

  @override
  Future<ChatWorkspace> loadWorkspace() async {
    _emitStatus(RepositoryConnectionStatus.connecting);
    try {
      final gatewayUrl = await _bootstrapStage(
        'gateway-discovery',
        _api.getGatewayUrl,
      );
      final snapshot = await _bootstrapStage(
        'gateway-session',
        () => _gateway.connectAndReadWorkspace(gatewayUrl),
      );
      final cached = await _bootstrapStage('cache-read', () async {
        await clearCacheOfOtherAccount(
          _cache,
          snapshot.currentUser['id']! as String,
          clearChatImages: _clearChatImages,
        );
        return _cache.readWorkspaceShell();
      });
      final workspace = await _bootstrapStage(
        'workspace-mapping',
        () async => _mapper
            .workspace(
              currentUser: snapshot.currentUser,
              guilds: snapshot.guilds,
              channelsByGuild: snapshot.channelsByGuild,
              rolesByGuild: snapshot.rolesByGuild,
              membersByGuild: snapshot.membersByGuild,
              emojisByGuild: snapshot.emojisByGuild,
              stickersByGuild: snapshot.stickersByGuild,
              directChannels: snapshot.directChannels,
              includeDirectMessagesSpace: true,
              currentUserRole: 'Discord user',
            )
            .restoreChannelActivityFrom(cached),
      );
      _adoptCurrentMember(workspace.currentMemberId);
      _adoptPrivateChannels(workspace, payloads: snapshot.directChannels);
      await _bootstrapStage(
        'cache-write',
        () => _cache.writeWorkspace(workspace),
      );
      _workspaceShown = true;
      return workspace;
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      final cached = await readOfflineWorkspace(_cache, _accountId);
      if (cached != null) {
        _adoptCurrentMember(cached.currentMemberId);
        _adoptPrivateChannels(cached);
        _workspaceShown = true;
        _emitStatus(RepositoryConnectionStatus.offline);
        return cached;
      }
      rethrow;
    }
  }

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
    String? aroundMessageId,
  }) async {
    // The held page goes out first, so the conversation is readable while
    // Discord is still being asked for the same one.
    final restored = beforeMessageId == null && aroundMessageId == null
        ? await readRestoredHistory(_cache, channelId, pageSize: _pageSize)
        : null;
    if (restored != null) _events.add(restored);
    try {
      final payloads = await _api.getChannelMessages(
        channelId,
        limit: _pageSize,
        beforeMessageId: beforeMessageId,
        aroundMessageId: aroundMessageId,
      );
      final history = _mapper.history(
        channelId,
        payloads,
        currentMemberId: _currentMemberId,
      );
      await _cache.writeChannelHistory(history, replaceExisting: false);
      return ChannelHistoryPage(
        history: history,
        hasMore: payloads.length == _pageSize,
      );
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      // The page already handed out is the answer; re-reading it would only
      // decode the same rows again.
      if (restored != null) {
        return ChannelHistoryPage(
          history: restored.history,
          hasMore: restored.hasMore,
          fromCache: true,
        );
      }
      final cached = await _cache.readChannelHistory(
        channelId,
        limit: _pageSize,
        beforeMessageId: beforeMessageId,
      );
      if (cached.messages.isEmpty) rethrow;
      return ChannelHistoryPage(
        history: cached,
        hasMore: cached.messages.length >= _pageSize,
        fromCache: true,
      );
    }
  }

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) async {
    try {
      final history = _mapper.history(
        channelId,
        await _api.getChannelPins(channelId),
        currentMemberId: _currentMemberId,
      );
      for (final message in history.messages) {
        await _cache.writeMessage(message);
      }
      return history;
    } on Object {
      return _cache.readPinnedMessages(channelId);
    }
  }

  @override
  Future<DirectConversation> openDirectConversation(String recipientId) async {
    final currentUserId = _currentMemberId;
    if (currentUserId == null) throw StateError('Workspace is not loaded');
    return _directMessages.open(recipientId, currentUserId);
  }

  @override
  Future<ConversationChannel> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) async {
    final workspace = await _cache.readWorkspaceShell();
    final parent = workspace?.channelOrNull(channelId);
    if (parent == null) throw StateError('Parent channel is not cached');
    final payload = await _api.createThreadFromMessage(
      channelId: channelId,
      messageId: messageId,
      name: name,
      autoArchiveDurationMinutes: autoArchiveDurationMinutes,
    );
    final channel = _mapper.channel(payload, parent.spaceId);
    if (channel == null) throw StateError('Discord returned an invalid thread');
    await _cache.writeChannel(channel);
    _events.add(ChannelUpsertedEvent(channel));
    return channel;
  }

  @override
  Future<ThreadPage> loadThreads(
    String parentId, {
    int offset = 0,
    Set<String> tagIds = const {},
  }) => _threads.loadThreads(parentId, offset: offset, tagIds: tagIds);

  @override
  Future<CreatedForumPost> createForumPost({
    required String channelId,
    required String name,
    required String content,
    required int autoArchiveDurationMinutes,
    List<PendingAttachment> attachments = const [],
    List<String> appliedTagIds = const [],
  }) => _threads.createForumPost(
    channelId: channelId,
    name: name,
    content: content,
    autoArchiveDurationMinutes: autoArchiveDurationMinutes,
    attachments: attachments,
    appliedTagIds: appliedTagIds,
  );

  @override
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
    bool textToSpeech = false,
  }) async {
    final payload = await _nonceFactory.sendDraft(
      channelId: channelId,
      body: body,
      attachments: attachments,
      replyToMessageId: replyToMessageId,
      suppressNotifications: suppressNotifications,
      textToSpeech: textToSpeech,
      send: (nonce) => _api.createMessage(
        channelId: channelId,
        content: body,
        nonce: nonce,
        attachments: attachments,
        replyToMessageId: replyToMessageId,
        suppressNotifications: suppressNotifications,
        textToSpeech: textToSpeech,
      ),
    );
    return _storeSentMessage(payload);
  }

  @override
  Future<ChatMessage> sendVoiceMessage({
    required String channelId,
    required String authorId,
    required PendingVoiceMessage voiceMessage,
  }) async {
    // As a draft with the file only, so a retry keeps its nonce.
    final payload = await _nonceFactory.sendDraft(
      channelId: channelId,
      body: '',
      attachments: [voiceMessage.attachment],
      replyToMessageId: null,
      suppressNotifications: false,
      textToSpeech: false,
      send: (nonce) => _api.createVoiceMessage(
        channelId: channelId,
        voiceMessage: voiceMessage,
        nonce: nonce,
      ),
    );
    return _storeSentMessage(payload);
  }

  @override
  Future<ReactionUsersPage> loadReactionUsers({
    required String channelId,
    required String messageId,
    required String emoji,
    required DiscordReactionType type,
    String? afterUserId,
    int limit = 100,
  }) async {
    final pageLimit = limit.clamp(1, 100);
    final payloads = await _api.getReactions(
      channelId: channelId,
      messageId: messageId,
      emoji: emoji,
      type: type,
      afterUserId: afterUserId,
      limit: pageLimit,
    );
    return _mapper.reactionUsers(payloads, limit: pageLimit);
  }

  @override
  Future<void> addSuperReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _api.addReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
    type: DiscordReactionType.burst,
  );

  @override
  Future<void> removeSuperReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _api.removeReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
    type: DiscordReactionType.burst,
  );

  /// A forward is a send with no words of its own: the reference names the
  /// source, and Discord answers with the snapshot it took.
  @override
  Future<ChatMessage> forwardMessage({
    required String sourceChannelId,
    required String sourceMessageId,
    required String targetChannelId,
  }) async => _storeSentMessage(
    await _api.createMessage(
      channelId: targetChannelId,
      content: '',
      nonce: _nonceFactory.next(),
      forwardOf: (channelId: sourceChannelId, messageId: sourceMessageId),
    ),
  );

  @override
  Future<ChatMessage> sendStickers({
    required String channelId,
    required String authorId,
    required List<String> stickerIds,
  }) async {
    if (stickerIds.isEmpty) {
      throw ArgumentError.value(stickerIds, 'stickerIds', 'must contain 1-3');
    }
    return _storeSentMessage(
      await _api.createMessage(
        channelId: channelId,
        content: '',
        nonce: _nonceFactory.next(),
        stickerIds: stickerIds,
      ),
    );
  }

  Future<ChatMessage> _storeSentMessage(Map<String, Object?> payload) async {
    final message = await _storeMessage(payload);
    // The gateway's copy may come later, and the channel must read as read
    // from the moment the send returns.
    _readState.acceptNewMessage(payload);
    return message;
  }

  @override
  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  }) async {
    final payload = await _api.editMessage(
      channelId: channelId,
      messageId: messageId,
      content: body,
    );
    return _storeMessage(
      payload,
      fallback: await _cache.readMessage(messageId),
    );
  }

  @override
  Future<ChatMessage> setSuppressEmbeds({
    required String channelId,
    required String messageId,
    required bool suppress,
  }) async {
    final held = await _cache.readMessage(messageId);
    final payload = await _api.editMessageFlags(
      channelId: channelId,
      messageId: messageId,
      suppressEmbeds: suppress,
      componentsV2: held?.hasFlag(DiscordMessageFlag.componentsV2) ?? false,
    );
    return _storeMessage(payload, fallback: held);
  }

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {
    await _api.deleteMessage(channelId: channelId, messageId: messageId);
    await _cache.deleteMessage(messageId);
  }

  @override
  void searchGuildMembers({
    required String guildId,
    required String query,
    int limit = 25,
  }) => _gateway.requestGuildMembers(
    guildId: guildId,
    query: query,
    limit: limit,
  );

  @override
  void requestGuildMembers({
    required String guildId,
    required List<String> userIds,
  }) => _gateway.requestGuildMembersByIds(guildId: guildId, userIds: userIds);

  @override
  Future<List<GuildScheduledEvent>> loadScheduledEvents(String spaceId) async {
    final payloads = await _api.getGuildScheduledEvents(spaceId);
    return [
      for (final payload in payloads)
        ?_mapper.guildScheduledEvent(payload, fallbackSpaceId: spaceId),
    ]..sort(GuildScheduledEvent.compareForDisplay);
  }

  @override
  Future<List<GuildScheduledEventAttendee>> loadEventAttendees({
    required String spaceId,
    required String eventId,
    int limit = 100,
  }) async {
    final payloads = await _api.getGuildScheduledEventUsers(
      guildId: spaceId,
      eventId: eventId,
      limit: limit,
    );
    return [for (final payload in payloads) ?_readAttendee(payload)];
  }

  /// Reads one row of the interested list.
  ///
  /// The nickname a server knows somebody by wins over their global name,
  /// because that is the name everybody else in that server sees them under.
  static GuildScheduledEventAttendee? _readAttendee(
    Map<String, Object?> payload,
  ) {
    final user = payload['user'];
    if (user is! Map) return null;
    final fields = user.cast<String, Object?>();
    final id = fields['id'];
    if (id is! String || id.isEmpty) return null;
    final member = payload['member'] is Map
        ? (payload['member']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final nickname = member['nick'];
    final global = fields['global_name'];
    final username = fields['username'];
    return GuildScheduledEventAttendee(
      userId: id,
      displayName: switch ((nickname, global, username)) {
        (final String nick, _, _) when nick.isNotEmpty => nick,
        (_, final String name, _) when name.isNotEmpty => name,
        (_, _, final String name) when name.isNotEmpty => name,
        _ => '',
      },
    );
  }

  @override
  Future<GuildScheduledEvent?> createScheduledEvent({
    required String spaceId,
    required GuildScheduledEventDraft draft,
  }) async {
    if (!draft.isValid) return null;
    final payload = await _api.createGuildScheduledEvent(
      guildId: spaceId,
      body: GuildScheduledEventEdit.encodeDraft(draft),
    );
    return _mapper.guildScheduledEvent(payload, fallbackSpaceId: spaceId);
  }

  @override
  Future<GuildScheduledEvent?> editScheduledEvent({
    required String spaceId,
    required String eventId,
    required GuildScheduledEventEdit edit,
  }) async {
    if (edit.isEmpty) return null;
    final payload = await _api.editGuildScheduledEvent(
      guildId: spaceId,
      eventId: eventId,
      body: edit.toJson(),
    );
    return _mapper.guildScheduledEvent(payload, fallbackSpaceId: spaceId);
  }

  @override
  Future<bool> deleteScheduledEvent({
    required String spaceId,
    required String eventId,
  }) async {
    try {
      await _api.deleteGuildScheduledEvent(guildId: spaceId, eventId: eventId);
      return true;
    } on DiscordApiException catch (error) {
      // An event somebody else already deleted, or one this account may not
      // manage, is refused. Neither is a fault here.
      if (error.statusCode == 403 || error.statusCode == 404) return false;
      rethrow;
    }
  }

  @override
  Future<bool> setEventInterest({
    required String spaceId,
    required String eventId,
    required bool interested,
    String? exceptionId,
  }) async {
    try {
      await _api.setGuildScheduledEventInterest(
        guildId: spaceId,
        eventId: eventId,
        interested: interested,
        exceptionId: exceptionId,
      );
    } on DiscordApiException catch (error) {
      // An event that has ended, or one this account cannot see, is refused.
      // That is an answer about the event, not a fault here.
      if (error.statusCode == 400 || error.statusCode == 403) return false;
      rethrow;
    }
    // The count moves when Discord echoes the change back. Patching it here
    // as well is how a count ends up permanently wrong by one.
    return true;
  }

  @override
  Future<void> resolveAutoModAlert({
    required String guildId,
    required String channelId,
    required String messageId,
    required AutoModAlertAction action,
  }) => _api.resolveAutoModAlert(
    guildId: guildId,
    channelId: channelId,
    messageId: messageId,
    actionType: action.code,
  );

  @override
  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _api.addReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );

  @override
  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _api.removeReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) => _setPinned(channelId, messageId, true);

  @override
  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) => _setPinned(channelId, messageId, false);

  Future<void> _setPinned(
    String channelId,
    String messageId,
    bool pinned,
  ) async {
    await _api.setPinned(
      channelId: channelId,
      messageId: messageId,
      pinned: pinned,
    );
    final message = await _cache.readMessage(messageId);
    if (message != null) {
      await _cache.writeMessage(message.copyWith(isPinned: pinned));
    }
  }

  /// Writes one gained guild to the cache and starts its live events.
  ///
  /// The workspace fold is the caller's; this is the transport half, which
  /// owns what a restart restores and the socket subscription Discord needs
  /// before it will push anything for the guild. The read state the account
  /// already carries for the guild's channels is folded here too: a join must
  /// show the unreads it had, not a fresh sheet where every channel reads. A
  /// guild this session already subscribed has it from READY or the first ask.
  Future<void> _persistGainedGuild(JoinedGuild guild) async {
    await _cache.writeGuild(guild);
    if (_gateway.subscribeGuildEvents(guild.space.id)) {
      unawaited(
        _readState.hydrateReadState(guild.space.id).catchError((Object _) {}),
      );
    }
  }

  /// Removes one left guild from the cache and drops its subscription.
  Future<void> _persistLeftGuild(String guildId) async {
    await _cache.deleteGuild(guildId);
    _gateway.forgetGuild(guildId);
  }

  @override
  Future<void> startTyping(String channelId) => _api.startTyping(channelId);

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) =>
      _cache.writeChannelActivity(channel);

  @override
  Future<void> close() async {
    await _sharedDispatches.stop(_gatewaySubscription);
    await _selfPresenceSubscription.cancel();
    await _presence.close();
    // Pending settings edits are written before the socket goes away; a
    // coalesced save that never left would be lost with no way to notice.
    await _userSettings.flush();
    await _userSettings.close();
    _messageSearch.close();
    await _userNotes.close();
    // An acknowledgement still on its debounce is a channel the account has
    // read; losing it would show the unread pip again on the next launch.
    await _readState.flush();
    await _readState.close();
    await _directCalls.close();
    await _voiceSignaling.close();
    await _threadMembership.close();
    await _stages.close();
    await _soundboard.close();
    await _favorites.close();
    await _messageComponents.close();
    await _goLive.close();
    await _summaries.close();
    await _relationships.close();
    await _memberLists.close();
    await _gateway.close();
    _api.close();
    await _cache.close();
    await _events.close();
  }
}
