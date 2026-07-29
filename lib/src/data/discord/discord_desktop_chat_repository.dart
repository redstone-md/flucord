import '../../domain/scheduled_event_repository.dart';
import '../../domain/age_verification.dart';
import '../../domain/multi_factor_auth.dart';
import '../../domain/auth_session.dart';
import '../../domain/family_centre.dart';
import '../../domain/account_standing.dart';
import '../../domain/automod_rule.dart';
import 'dart:async';
import 'dart:developer' as developer;

import '../../domain/chat_cache.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../domain/guild_management_repository.dart';
import '../../domain/guild_member_list.dart';
import '../../domain/guild_member_list_repository.dart';
import '../../domain/message_search_repository.dart';
import '../../domain/moderation_repository.dart';
import '../../domain/presence_repository.dart';
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
import '../../domain/thread_membership.dart';
import '../../domain/user_profile.dart';
import '../../domain/voice_connection.dart';
import '../../domain/voice_dave.dart';
import 'discord_desktop_api_client.dart';
import 'discord_read_state_repository.dart';
import 'discord_user_settings_repository.dart';
import 'discord_desktop_gateway_client.dart';
import 'discord_direct_call_service.dart';
import 'discord_gateway_client.dart';
import 'discord_mapper.dart';
import 'discord_member_list_handler.dart';
import 'discord_message_search_service.dart';
import 'discord_message_nonce_factory.dart';
import 'discord_presence_service.dart';
import 'discord_rest_client.dart';
import 'discord_user_profile_repository.dart';
import 'discord_application_command_service.dart';
import 'discord_conversation_summary_service.dart';
import 'discord_go_live_service.dart';
import 'discord_message_component_service.dart';
import 'discord_gif_service.dart';
import 'discord_soundboard_service.dart';
import 'discord_stage_service.dart';
import 'discord_thread_membership_service.dart';
import 'discord_voice_signaling_service.dart';

part 'discord_desktop_chat_events.dart';
part 'discord_desktop_chat_session.dart';

final class DiscordDesktopChatRepository
    implements
        ChatRepository,
        GuildMemberListRepository,
        ScheduledEventRepository {
  DiscordDesktopChatRepository(
    this._api,
    this._gateway,
    this._cache, {
    DiscordMapper? mapper,
    DiscordMessageNonceFactory? nonceFactory,
    VoiceDaveService? daveService,
  }) : _mapper = mapper ?? DiscordMapper(),
       _nonceFactory = nonceFactory ?? DiscordMessageNonceFactory(),
       _userSettings = DiscordUserSettingsRepository(_api),
       _readState = DiscordReadStateRepository(_api),
       _threadMembership = DiscordThreadMembershipService(_api),
       _stages = DiscordStageService(_api),
       _soundboard = DiscordSoundboardService(_api),
       _gifs = DiscordGifService(_api),
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
         nativeDaveService: daveService,
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
    // R03: a re-IDENTIFY may echo the cache versions the last READY carried, so
    // the socket asks the read-state store for them at the moment it needs
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
  final DiscordStageService _stages;
  final DiscordSoundboardService _soundboard;
  final DiscordGifService _gifs;
  final DiscordApplicationCommandService _applicationCommands;
  final DiscordMessageComponentService _messageComponents;
  // Built after construction because the adapter reads the signed-in account
  // off this repository, which does not exist yet in the initialiser list.
  final DiscordConversationSummaryService _summaries =
      DiscordConversationSummaryService();
  late final DiscordGoLiveService _goLive = DiscordGoLiveService(
    _DesktopGoLiveGateway(_gateway, () => _currentMemberId),
  );
  late final DiscordUserProfileRepository _userProfile =
      DiscordUserProfileRepository(_api);
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();
  late final StreamSubscription<DiscordGatewayEvent> _gatewaySubscription;
  late final DiscordMemberListHandler _memberLists;
  late final DiscordMessageSearchService _messageSearch;
  late final DiscordPresenceService _presence;
  late final DiscordDirectCallService _directCalls;
  late final StreamSubscription<SelfPresence> _selfPresenceSubscription;
  String? _currentMemberId;

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

  @override
  ThreadMembershipRepository? get threadMembership => _threadMembership;

  @override
  StageRepository? get stages => _stages;

  @override
  SoundboardRepository? get soundboard => _soundboard;

  @override
  GifRepository? get gifs => _gifs;

  @override
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
      final cached = await _bootstrapStage('cache-read', _cache.readWorkspace);
      final workspace = await _bootstrapStage(
        'workspace-mapping',
        () async => _mapper
            .workspace(
              currentUser: snapshot.currentUser,
              guilds: snapshot.guilds,
              channelsByGuild: snapshot.channelsByGuild,
              rolesByGuild: snapshot.rolesByGuild,
              membersByGuild: snapshot.membersByGuild,
              directChannels: snapshot.directChannels,
              includeDirectMessagesSpace: true,
              currentUserRole: 'Discord user',
            )
            .restoreChannelActivityFrom(cached),
      );
      _adoptCurrentMember(workspace.currentMemberId);
      _adoptPrivateChannels(workspace);
      await _bootstrapStage(
        'cache-write',
        () => _cache.writeWorkspace(workspace),
      );
      return workspace;
    } catch (error) {
      if (error is DiscordApiException && error.isUnauthorized) rethrow;
      final cached = await _cache.readWorkspace();
      if (cached != null) {
        _adoptCurrentMember(cached.currentMemberId);
        _adoptPrivateChannels(cached);
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
  }) async {
    try {
      final payloads = await _api.getChannelMessages(
        channelId,
        limit: _pageSize,
        beforeMessageId: beforeMessageId,
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
      final cached = await _cache.readChannelHistory(channelId);
      if (cached.messages.isEmpty) rethrow;
      return ChannelHistoryPage(history: cached, hasMore: false);
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
    final mapped = _mapper.directMessage(
      await _api.createDirectMessageChannel(recipientId),
      currentUserId,
    );
    if (mapped == null) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Discord returned an invalid direct message channel',
      );
    }
    await _cache.writeSpace(_mapper.directMessagesSpace);
    await _cache.writeChannel(mapped.channel);
    await _cache.writeMember(mapped.recipient);
    _events.add(SpaceUpsertedEvent(_mapper.directMessagesSpace));
    _events.add(ChannelUpsertedEvent(mapped.channel));
    _events.add(MemberUpsertedEvent(mapped.recipient));
    return DirectConversation(
      channel: mapped.channel,
      recipient: mapped.recipient,
    );
  }

  @override
  Future<ConversationChannel> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) async {
    final workspace = await _cache.readWorkspace();
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
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
  }) async {
    final payload = await _api.createMessage(
      channelId: channelId,
      content: body,
      nonce: _nonceFactory.next(),
      attachments: attachments,
      replyToMessageId: replyToMessageId,
      suppressNotifications: suppressNotifications,
    );
    return _storeMessage(payload);
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

  @override
  Future<void> startTyping(String channelId) => _api.startTyping(channelId);

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) =>
      _cache.writeChannelActivity(channel);

  @override
  Future<void> close() async {
    await _gatewaySubscription.cancel();
    await _selfPresenceSubscription.cancel();
    await _presence.close();
    // Pending settings edits are written before the socket goes away; a
    // coalesced save that never left would be lost with no way to notice.
    await _userSettings.flush();
    await _userSettings.close();
    _messageSearch.close();
    // An acknowledgement still on its debounce is a channel the account has
    // read; losing it would show the unread pip again on the next launch.
    await _readState.flush();
    await _readState.close();
    await _directCalls.close();
    await _voiceSignaling.close();
    await _threadMembership.close();
    await _stages.close();
    await _soundboard.close();
    await _messageComponents.close();
    await _goLive.close();
    await _summaries.close();
    await _memberLists.close();
    await _gateway.close();
    _api.close();
    await _cache.close();
    await _events.close();
  }
}

/// Adapts the desktop gateway to the frames Go Live needs.
///
/// The service is written against the five frames rather than the whole
/// gateway so it can be tested without a socket, and this is the seam.
final class _DesktopGoLiveGateway implements DiscordGoLiveGateway {
  const _DesktopGoLiveGateway(this._gateway, this._currentUserId);

  final DiscordDesktopGatewayClient _gateway;
  final String? Function() _currentUserId;

  @override
  String? get currentUserId => _currentUserId();

  @override
  void sendStreamCreate({
    required String type,
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) => _gateway.sendStreamCreate(
    type: type,
    channelId: channelId,
    guildId: guildId,
    preferredRegion: preferredRegion,
  );

  @override
  void sendStreamDelete(String streamKey) =>
      _gateway.sendStreamDelete(streamKey);

  @override
  void sendStreamWatch(String streamKey) => _gateway.sendStreamWatch(streamKey);

  @override
  void sendStreamPing(String streamKey) => _gateway.sendStreamPing(streamKey);

  @override
  void sendStreamSetPaused(String streamKey, {required bool paused}) =>
      _gateway.sendStreamSetPaused(streamKey, paused: paused);
}
