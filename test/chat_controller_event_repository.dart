part of 'chat_controller_test.dart';

final class _EventRepository
    implements
        ChatRepository,
        ScheduledEventRepository,
        GuildMemberListRepository {
  @override
  UserProfileRepository? get userProfile => _delegate.userProfile;

  @override
  ThreadMembershipRepository? get threadMembership =>
      _delegate.threadMembership;

  @override
  StageRepository? get stages => _delegate.stages;

  @override
  SoundboardRepository? get soundboard => _delegate.soundboard;

  @override
  GifRepository? get gifs => _delegate.gifs;

  @override
  ApplicationCommandRepository? get applicationCommands =>
      _delegate.applicationCommands;

  @override
  MessageComponentRepository? get messageComponents =>
      _delegate.messageComponents;

  @override
  GoLiveRepository? get goLive => _delegate.goLive;

  @override
  ConversationSummaryRepository? get conversationSummaries =>
      _delegate.conversationSummaries;

  final MockChatRepository _delegate = MockChatRepository(
    latency: Duration.zero,
  );
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();

  void emit(ChatRepositoryEvent event) => _events.add(event);

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  @override
  VoiceSignalingService? get voiceSignaling => null;

  @override
  UserSettingsRepository? get userSettings => null;

  @override
  ReadStateRepository? get readState => null;

  @override
  DirectCallService? get directCalls => null;

  @override
  GuildManagementRepository? get guildManagement => null;

  @override
  ModerationRepository? get moderation => null;

  @override
  SafetyHubRepository? get safetyHub => null;

  @override
  FamilyCentreRepository? get familyCentre => null;

  @override
  AuthSessionRepository? get authSessions => null;

  @override
  MultiFactorAuthRepository? get multiFactorAuth => null;

  @override
  AgeVerificationRepository? get ageVerification => null;

  @override
  MessageSearchRepository? get messageSearch => null;

  @override
  PresenceService? get presence => null;

  @override
  Future<ChatWorkspace> loadWorkspace() => _delegate.loadWorkspace();

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
  }) =>
      _delegate.loadChannelHistory(channelId, beforeMessageId: beforeMessageId);

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) =>
      _delegate.loadPinnedMessages(channelId);

  @override
  Future<DirectConversation> openDirectConversation(String recipientId) =>
      _delegate.openDirectConversation(recipientId);

  @override
  Future<ConversationChannel> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) => _delegate.createThreadFromMessage(
    channelId: channelId,
    messageId: messageId,
    name: name,
    autoArchiveDurationMinutes: autoArchiveDurationMinutes,
  );

  @override
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
  }) => _delegate.sendMessage(
    channelId: channelId,
    authorId: authorId,
    body: body,
    attachments: attachments,
    replyToMessageId: replyToMessageId,
    suppressNotifications: suppressNotifications,
  );

  @override
  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  }) => _delegate.editMessage(
    channelId: channelId,
    messageId: messageId,
    body: body,
  );

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) => _delegate.deleteMessage(channelId: channelId, messageId: messageId);

  /// What the controller asked for, so a test can check it asked at all.
  ({
    String guildId,
    String channelId,
    String messageId,
    AutoModAlertAction action,
  })?
  resolvedAlert;

  /// What the controller asked for, so a test can check it asked at all.
  final List<(String, String, bool)> rsvps = [];
  bool failNextRsvp = false;

  @override
  Future<List<GuildScheduledEvent>> loadScheduledEvents(String spaceId) =>
      _delegate.loadScheduledEvents(spaceId);

  /// What the controller asked of the event routes.
  final List<GuildScheduledEventDraft> created = [];
  final List<GuildScheduledEventEdit> edited = [];
  final List<String> deleted = [];
  bool failNextEventWrite = false;
  bool acceptEventWrite = true;

  /// Who to answer the interested list with, and what was asked for.
  final List<String> attendeeRequests = [];
  bool failNextAttendees = false;

  /// What the composer asked the guild about.
  final List<(String, String)> memberSearches = [];

  /// The rest of the roster contract, which these tests do not exercise: the
  /// controller only needs the repository to be one for the search to reach it.
  @override
  Stream<GuildMemberList> get memberListUpdates => const Stream.empty();

  @override
  String memberListIdFor({
    required String guildId,
    required String channelId,
  }) => 'everyone';

  @override
  GuildMemberList? memberListFor({
    required String guildId,
    required String listId,
  }) => null;

  @override
  void subscribeMemberRanges({
    required String guildId,
    required String channelId,
    required List<List<int>> ranges,
  }) {}

  @override
  void unsubscribeMemberRanges({
    required String guildId,
    required String channelId,
  }) {}

  @override
  void searchGuildMembers({
    required String guildId,
    required String query,
    int limit = 25,
  }) => memberSearches.add((guildId, query));

  @override
  Future<List<GuildScheduledEventAttendee>> loadEventAttendees({
    required String spaceId,
    required String eventId,
    int limit = 100,
  }) async {
    if (failNextAttendees) {
      failNextAttendees = false;
      throw StateError('attendees failed');
    }
    attendeeRequests.add(eventId);
    return const [
      GuildScheduledEventAttendee(userId: 'user-1', displayName: 'Mira'),
    ];
  }

  @override
  Future<GuildScheduledEvent?> createScheduledEvent({
    required String spaceId,
    required GuildScheduledEventDraft draft,
  }) async {
    if (failNextEventWrite) {
      failNextEventWrite = false;
      throw StateError('create failed');
    }
    if (!acceptEventWrite) return null;
    created.add(draft);
    return GuildScheduledEvent(
      id: 'event-new',
      spaceId: spaceId,
      name: draft.name,
      scheduledStartTime: draft.startTime,
      entityType: draft.entityType,
      status: GuildScheduledEventStatus.scheduled,
    );
  }

  @override
  Future<GuildScheduledEvent?> editScheduledEvent({
    required String spaceId,
    required String eventId,
    required GuildScheduledEventEdit edit,
  }) async {
    if (failNextEventWrite) {
      failNextEventWrite = false;
      throw StateError('edit failed');
    }
    if (!acceptEventWrite) return null;
    edited.add(edit);
    return GuildScheduledEvent(
      id: eventId,
      spaceId: spaceId,
      name: edit['name'] as String? ?? 'Forge night',
      scheduledStartTime: DateTime.utc(2026, 8),
      entityType: GuildScheduledEventEntityType.external,
      status: GuildScheduledEventStatus.scheduled,
    );
  }

  @override
  Future<bool> deleteScheduledEvent({
    required String spaceId,
    required String eventId,
  }) async {
    if (failNextEventWrite) {
      failNextEventWrite = false;
      throw StateError('delete failed');
    }
    if (!acceptEventWrite) return false;
    deleted.add(eventId);
    return true;
  }

  @override
  Future<bool> setEventInterest({
    required String spaceId,
    required String eventId,
    required bool interested,
    String? exceptionId,
  }) async {
    if (failNextRsvp) {
      failNextRsvp = false;
      throw StateError('rsvp failed');
    }
    rsvps.add((spaceId, eventId, interested));
    return true;
  }

  @override
  Future<void> resolveAutoModAlert({
    required String guildId,
    required String channelId,
    required String messageId,
    required AutoModAlertAction action,
  }) async {
    resolvedAlert = (
      guildId: guildId,
      channelId: channelId,
      messageId: messageId,
      action: action,
    );
  }

  @override
  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _delegate.addReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );

  @override
  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _delegate.removeReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) => _delegate.pinMessage(channelId: channelId, messageId: messageId);

  @override
  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) => _delegate.unpinMessage(channelId: channelId, messageId: messageId);

  @override
  Future<void> startTyping(String channelId) =>
      _delegate.startTyping(channelId);

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) =>
      _delegate.saveChannelActivity(channel);

  @override
  Future<void> close() async {}
}
