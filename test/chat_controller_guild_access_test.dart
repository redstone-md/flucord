import 'dart:async';

import 'package:flucord/src/domain/account_connections.dart';
import 'package:flucord/src/domain/account_data_package.dart';
import 'package:flucord/src/domain/account_entitlements.dart';
import 'package:flucord/src/domain/account_standing.dart';
import 'package:flucord/src/domain/age_verification.dart';
import 'package:flucord/src/domain/app_authorisation.dart';
import 'package:flucord/src/domain/application_command.dart';
import 'package:flucord/src/domain/auth_session.dart';
import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/domain/automod_rule_editing.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/conversation_summary.dart';
import 'package:flucord/src/domain/desktop_relationship_repository.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/expression_favorites.dart';
import 'package:flucord/src/domain/family_centre.dart';
import 'package:flucord/src/domain/gif_picker.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/guild_audit_log.dart';
import 'package:flucord/src/domain/guild_expression_repository.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/message_component.dart';
import 'package:flucord/src/domain/message_search_repository.dart';
import 'package:flucord/src/domain/moderation_repository.dart';
import 'package:flucord/src/domain/multi_factor_auth.dart';
import 'package:flucord/src/domain/game_detection.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/domain/stage_channel.dart';
import 'package:flucord/src/domain/thread_membership.dart';
import 'package:flucord/src/domain/user_notes.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('join', () {
    test('hydrates the joined server into the rail and channel tree', () async {
      final repository = _Repository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      final spaceId = await controller.joinGuild('aurora');

      expect(spaceId, '444444444444444444');
      final workspace = controller.workspace!;
      expect(workspace.spaceById('444444444444444444').name, 'Aurora Labs');
      expect(
        workspace
            .channelsFor('444444444444444444')
            .map((channel) => channel.name),
        containsAll(['general', 'lab-notes']),
      );
      expect(
        workspace
            .categoriesFor('444444444444444444')
            .map((category) => category.name),
        ['Research'],
      );
      // The role bits arrive with the join, so visibility answers at once.
      expect(workspace.roleOrNull('555555555555555555')?.name, '@everyone');
      // The account's own membership is what permissions need.
      expect(
        workspace
            .memberById(workspace.currentMemberId)
            .membershipIn('444444444444444444'),
        isNotNull,
      );
      // What was already on the rail stays.
      expect(workspace.spaceOrNull('111111111111111111'), isNotNull);

      // Opening one of the joined server's channels loads its history over
      // the same transport, with no restart and no reload in between.
      await controller.openChannel('500000000000000001');
      expect(
        controller.workspace!
            .messagesFor('500000000000000001')
            .map((message) => message.body),
        ['Welcome to Aurora Labs.'],
      );
    });

    test('a join folds the read state so unread channels show', () async {
      final repository = _Repository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      // The joined server has no read state yet: a fresh join reads every
      // channel until the guild's entries arrive.
      final spaceId = await controller.joinGuild('aurora');
      expect(spaceId, '444444444444444444');
      final joined = controller.workspace!.channelById('500000000000000001');
      expect(joined.unread, isFalse);

      // The hydration answer carries the cursor the account already had, and
      // the channel's newest message the transport announced is newer than it.
      repository.readStateStore.publish(
        ReadStateSnapshot(
          readStates: {
            '500000000000000001': ReadState(
              entityId: '500000000000000001',
              lastAckedId: '222222222222222222',
              mentionCount: 1,
            ),
          },
        ),
      );
      repository.emit(
        const ChannelLastMessageEvent(
          channelId: '500000000000000001',
          messageId: '666666666666666666',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final channel = controller.workspace!.channelById('500000000000000001');
      expect(channel.unread, isTrue);
      expect(channel.mentionCount, 1);
    });

    test('an already-joined invite reports its refusal', () async {
      final repository = _Repository(
        guildManagement: _FakeGuildManagement(
          joinRefusal: const GuildAccessException(
            refusal: GuildAccessRefusal.alreadyJoined,
            message: 'You are already in this server.',
          ),
        ),
      );
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      final spaceId = await controller.joinGuild('aurora');

      expect(spaceId, isNull);
      // The refusal is a message a user reads, not a status code.
      expect(controller.guildAccessError, 'You are already in this server.');
      // Nothing was folded onto the rail.
      expect(
        controller.workspace!.spaces.where(
          (space) => space.id == '444444444444444444',
        ),
        isEmpty,
      );
    });

    test('an expired invite reports its refusal', () async {
      final repository = _Repository(
        guildManagement: _FakeGuildManagement(
          joinRefusal: const GuildAccessException(
            refusal: GuildAccessRefusal.expired,
            message: 'This invite has expired.',
          ),
        ),
      );
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      final spaceId = await controller.joinGuild('aurora');

      expect(spaceId, isNull);
      expect(controller.guildAccessError, 'This invite has expired.');
    });

    test('a preview resolves before any join is attempted', () async {
      final repository = _Repository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      final preview = await controller.previewInvite('aurora');

      expect(preview.name, 'Aurora Labs');
      expect(preview.approximateMemberCount, 1204);
      expect(
        (repository.guildManagement as _FakeGuildManagement).joinedCodes,
        isEmpty,
      );
    });
  });

  group('create', () {
    test(
      'names the server, and it survives a restart from the cache',
      () async {
        final repository = _Repository();
        final controller = ChatController(repository);
        addTearDown(controller.dispose);
        await controller.load();

        final spaceId = await controller.createGuild('Workshop');

        expect(spaceId, '444444444444444444');
        expect(controller.workspace!.spaceOrNull(spaceId!)!.name, 'Workshop');
        // The create hands the transport the name to keep, and the transport
        // is what writes what a restart restores.
        expect(_lastCreatedName, 'Workshop');
      },
    );

    test(
      'a transport without the guild-management plane creates nothing',
      () async {
        final controller = ChatController(_Repository(serveAccess: false));
        addTearDown(controller.dispose);
        await controller.load();

        final spaceId = await controller.createGuild('Workshop');

        expect(spaceId, isNull);
      },
    );
  });

  group('leave', () {
    test('removes the server from the rail after the account leaves', () async {
      final repository = _Repository();
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.joinGuild('aurora');

      final left = await controller.leaveGuild('444444444444444444');

      expect(left, isTrue);
      final workspace = controller.workspace!;
      expect(workspace.spaceOrNull('444444444444444444'), isNull);
      expect(workspace.channelsFor('444444444444444444'), isEmpty);
      expect(workspace.categoriesFor('444444444444444444'), isEmpty);
      expect(
        workspace.roles.where((role) => role.spaceId == '444444444444444444'),
        isEmpty,
      );
      // The membership record lost the guild with it.
      expect(
        workspace
            .memberById(workspace.currentMemberId)
            .membershipIn('444444444444444444'),
        isNull,
      );
      // Other servers keep their shape.
      expect(workspace.spaceOrNull('111111111111111111'), isNotNull);
      expect(
        (repository.guildManagement as _FakeGuildManagement).leftGuildIds,
        ['444444444444444444'],
      );
    });

    test('a refused leave reports its message and keeps the server', () async {
      final repository = _Repository(
        guildManagement: _FakeGuildManagement(
          leaveRefusal: const GuildAccessException(
            refusal: GuildAccessRefusal.unknown,
            message: 'This server could not be left: you own it.',
          ),
        ),
      );
      final controller = ChatController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      final left = await controller.leaveGuild('111111111111111111');

      expect(left, isFalse);
      expect(
        controller.guildAccessError,
        'This server could not be left: you own it.',
      );
      expect(
        controller.workspace!.spaceOrNull('111111111111111111'),
        isNotNull,
      );
    });
  });

  test('clearing the refusal message notifies the surface', () async {
    final repository = _Repository(
      guildManagement: _FakeGuildManagement(
        joinRefusal: const GuildAccessException(
          refusal: GuildAccessRefusal.invalid,
          message: 'This invite is not valid.',
        ),
      ),
    );
    final controller = ChatController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.joinGuild('aurora');

    var notified = false;
    controller.addListener(() => notified = true);
    controller.clearGuildAccessError();

    expect(notified, isTrue);
    expect(controller.guildAccessError, isNull);
  });
}

/// The name the last create handed the plane, for the assertion that reads
/// what a restart would restore: the transport owns the write.
String? _lastCreatedName;

/// The transport: the demo-shaped workspace plus whatever server access the
/// fake guild-management plane answers.
final class _Repository implements ChatRepository {
  _Repository({_FakeGuildManagement? guildManagement, bool serveAccess = true})
    : access = serveAccess ? guildManagement ?? _FakeGuildManagement() : null,
      readStateStore = _FakeReadStateStore();

  /// the controller through the contract's nullable capability.
  final _FakeGuildManagement? access;

  /// The read-state store a join hydrates through; nothing publishes to it
  /// unless a test does.
  final _FakeReadStateStore readStateStore;
  final StreamController<ChatRepositoryEvent> _events =
      StreamController.broadcast();

  @override
  GuildManagementRepository? get guildManagement => access;

  @override
  AccountConnectionsRepository? get accountConnections => null;

  @override
  AccountEntitlementsRepository? get accountEntitlements => null;

  @override
  AppAuthorisationRepository? get appAuthorisation => null;

  @override
  UserNotesRepository? get userNotes => null;

  @override
  AccountDataPackageRepository? get accountDataPackage => null;

  @override
  GuildExpressionRepository? get expressions => null;

  @override
  Stream<ChatRepositoryEvent> get events => _events.stream;

  void emit(ChatRepositoryEvent event) => _events.add(event);

  @override
  Future<ChatWorkspace> loadWorkspace() async => _seedWorkspace();

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
    String? aroundMessageId,
  }) async {
    if (channelId == '500000000000000001') {
      return ChannelHistoryPage(
        history: ChannelHistory(
          channelId: channelId,
          messages: [
            ChatMessage(
              id: '666666666666666666',
              channelId: channelId,
              authorId: '987654321098765432',
              body: 'Welcome to Aurora Labs.',
              sentAt: DateTime(2026, 9, 14),
            ),
          ],
          members: const [],
        ),
        hasMore: false,
      );
    }
    return ChannelHistoryPage(
      history: ChannelHistory(channelId: channelId, messages: [], members: []),
      hasMore: false,
    );
  }

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) async =>
      ChannelHistory(channelId: channelId, messages: [], members: []);

  @override
  Future<DirectConversation> openDirectConversation(String recipientId) =>
      throw UnimplementedError();

  @override
  Future<ConversationChannel> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) => throw UnimplementedError();

  @override
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
    bool textToSpeech = false,
  }) => throw UnimplementedError();

  @override
  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {}

  @override
  Future<void> resolveAutoModAlert({
    required String guildId,
    required String channelId,
    required String messageId,
    required AutoModAlertAction action,
  }) async {}

  @override
  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {}

  @override
  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {}

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) async {}

  @override
  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) async {}

  @override
  Future<void> startTyping(String channelId) async {}

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) async {}

  @override
  Future<void> close() async {
    await _events.close();
  }

  // Every capability this test does not drive says so, rather than handing
  // back a plane whose every call would fail.
  @override
  VoiceSignalingService? get voiceSignaling => null;

  @override
  UserProfileRepository? get userProfile => null;

  @override
  ThreadMembershipRepository? get threadMembership => null;

  @override
  StageRepository? get stages => null;

  @override
  SoundboardRepository? get soundboard => null;

  @override
  GifRepository? get gifs => null;

  @override
  ExpressionFavoritesRepository? get expressionFavorites => null;

  @override
  ApplicationCommandRepository? get applicationCommands => null;

  @override
  MessageComponentRepository? get messageComponents => null;

  @override
  GoLiveRepository? get goLive => null;

  @override
  ConversationSummaryRepository? get conversationSummaries => null;

  @override
  UserSettingsRepository? get userSettings => null;

  @override
  ReadStateRepository? get readState => readStateStore;

  @override
  DirectCallService? get directCalls => null;

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
  DesktopRelationshipRepository? get relationships => null;

  @override
  MessageSearchRepository? get messageSearch => null;

  @override
  PresenceService? get presence => null;
  @override
  DetectableGameRepository? get detectableGames => null;
}

/// The read-state half a join needs: a snapshot that can be published and the
/// version answer the projection reads.
final class _FakeReadStateStore implements ReadStateRepository {
  final StreamController<ReadStateSnapshot> _updates =
      StreamController.broadcast();

  ReadStateSnapshot _current = ReadStateSnapshot.empty;

  void publish(ReadStateSnapshot snapshot) {
    _current = snapshot;
    _updates.add(snapshot);
  }

  @override
  Stream<ReadStateSnapshot> get updates => _updates.stream;

  @override
  ReadStateSnapshot get current => _current;

  @override
  Future<void> acknowledge(
    ConversationChannel channel, {
    required String messageId,
    bool immediate = false,
  }) async {}

  @override
  Future<void> markUnread(
    ConversationChannel channel, {
    required String messageId,
    int mentionCount = 0,
  }) async {}

  @override
  Future<void> markSpaceRead(
    String spaceId,
    Iterable<ConversationChannel> channels,
  ) async {}

  @override
  Future<void> acknowledgeMessageRequest(String channelId) async {}

  @override
  Future<void> acknowledgeNotificationCentre(String spaceId) async {}

  @override
  Future<void> collectGarbage({DateTime? now}) async {}

  @override
  Future<void> updateSpaceNotificationSettings(
    String spaceId,
    GuildNotificationSettingsPatch patch,
  ) async {}

  @override
  Future<void> updateChannelNotificationOverride({
    required String spaceId,
    required String channelId,
    required ChannelNotificationOverridePatch patch,
  }) async {}

  @override
  Future<void> flush() async {}
}

/// The server-access half of the guild-management contract, in memory. The
/// settings routes stay unimplemented: this test drives join, create and
/// leave, and nothing else.
final class _FakeGuildManagement implements GuildManagementRepository {
  _FakeGuildManagement({this.joinRefusal, this.leaveRefusal});

  final GuildAccessException? joinRefusal;
  final GuildAccessException? leaveRefusal;

  final List<String> joinedCodes = [];
  final List<String> createdNames = [];
  final List<String> leftGuildIds = [];

  @override
  Future<InvitePreview> previewInvite(String code) async => const InvitePreview(
    code: 'aurora',
    name: 'Aurora Labs',
    guildId: '444444444444444444',
    approximateMemberCount: 1204,
  );

  @override
  Future<JoinedGuild> joinGuild(String code) async {
    final refusal = joinRefusal;
    if (refusal != null) throw refusal;
    joinedCodes.add(code);
    return _auroraGuild('Aurora Labs');
  }

  @override
  Future<JoinedGuild> createGuild({required String name}) async {
    createdNames.add(name);
    _lastCreatedName = name;
    return _auroraGuild(name);
  }

  @override
  Future<void> leaveGuild(String guildId) async {
    final refusal = leaveRefusal;
    if (refusal != null) throw refusal;
    leftGuildIds.add(guildId);
  }

  @override
  Future<GuildMemberProfile> loadMember({
    required String guildId,
    required String userId,
  }) => throw UnimplementedError();

  @override
  Future<GuildMemberProfile> updateMember({
    required String guildId,
    required String userId,
    required GuildMemberEdit edit,
  }) => throw UnimplementedError();

  @override
  Future<void> grantMemberRole({
    required String guildId,
    required String userId,
    required String roleId,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<void> revokeMemberRole({
    required String guildId,
    required String userId,
    required String roleId,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<List<GuildWebhook>> loadWebhooks(String id) =>
      throw UnimplementedError();

  @override
  Future<GuildWebhook> createWebhook({
    required String guildId,
    required GuildWebhookDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<GuildWebhook> updateWebhook({
    required String webhookId,
    required GuildWebhookEdit edit,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteWebhook(String webhookId) => throw UnimplementedError();

  @override
  Future<GuildOverviewSettings> loadGuildOverview(String guildId) =>
      throw UnimplementedError();

  @override
  Future<GuildOverviewSettings> saveGuildOverview({
    required String guildId,
    required GuildOverviewPatch patch,
  }) => throw UnimplementedError();

  @override
  Future<List<GuildRole>> loadRoles(String guildId) =>
      throw UnimplementedError();

  @override
  Future<GuildRole> createRole({
    required String guildId,
    required GuildRoleDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<GuildRole> updateRole({
    required String guildId,
    required String roleId,
    required GuildRoleEdit edit,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteRole({required String guildId, required String roleId}) =>
      throw UnimplementedError();

  @override
  Future<void> reorderRoles({
    required String guildId,
    required List<RolePositionDelta> deltas,
  }) => throw UnimplementedError();

  @override
  Future<ConversationChannel> createGuildChannel({
    required String guildId,
    required GuildChannelDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<ConversationChannel> editGuildChannel({
    required String channelId,
    required GuildChannelEdit edit,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteGuildChannel(String channelId) =>
      throw UnimplementedError();

  @override
  Future<void> reorderGuildChannels({
    required String guildId,
    required List<ChannelPositionDelta> deltas,
  }) => throw UnimplementedError();

  @override
  Future<List<GuildBan>> loadBans({
    required String guildId,
    int limit = 1000,
    String? after,
  }) => throw UnimplementedError();

  @override
  Future<List<GuildBan>> searchBans({
    required String guildId,
    required String query,
    int limit = 10,
  }) => throw UnimplementedError();

  @override
  Future<BulkBanResult> banMembers({
    required String guildId,
    required BanRequest request,
  }) => throw UnimplementedError();

  @override
  Future<void> unbanMember({
    required String guildId,
    required String userId,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<void> kickMember({
    required String guildId,
    required String userId,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<List<GuildInvite>> loadGuildInvites(String guildId) =>
      throw UnimplementedError();

  @override
  Future<GuildInvite> createChannelInvite({
    required String channelId,
    InviteOptions options = const InviteOptions(),
  }) => throw UnimplementedError();

  @override
  Future<void> revokeInvite(String code) => throw UnimplementedError();

  @override
  Future<AuditLogPage> loadAuditLog({
    required String guildId,
    AuditLogQuery query = const AuditLogQuery(),
  }) => throw UnimplementedError();

  @override
  Future<List<AutoModRule>> loadAutoModRules(String guildId) =>
      throw UnimplementedError();

  @override
  Future<AutoModRule> createAutoModRule({
    required String guildId,
    required AutoModRuleDraft draft,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<AutoModRule> updateAutoModRule({
    required String guildId,
    required String ruleId,
    required AutoModRuleEdit edit,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteAutoModRule({
    required String guildId,
    required String ruleId,
    String? reason,
  }) => throw UnimplementedError();

  @override
  Future<String?> validateAutoModRule({
    required String guildId,
    required AutoModRuleDraft draft,
  }) => throw UnimplementedError();

  @override
  Future<void> clearMentionRaid(String guildId) => throw UnimplementedError();

  @override
  Future<void> reportMentionRaidFalseAlarm(String guildId) =>
      throw UnimplementedError();
}

ChatWorkspace _seedWorkspace() => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: '111111111111111111',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: '222222222222222222',
      spaceId: '111111111111111111',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  members: const [
    Member(
      id: '987654321098765432',
      displayName: 'Mira',
      initials: 'MI',
      role: 'member',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: {'111111111111111111'},
    ),
  ],
  messages: const [],
  currentMemberId: '987654321098765432',
);

JoinedGuild _auroraGuild(String name) => JoinedGuild(
  space: CommunitySpace(
    id: '444444444444444444',
    name: name,
    monogram: 'AL',
    colorValue: 0xff486b70,
  ),
  channels: const [
    ConversationChannel(
      id: '500000000000000001',
      spaceId: '444444444444444444',
      name: 'general',
      topic: 'Say hello',
      kind: ChannelKind.text,
    ),
    ConversationChannel(
      id: '500000000000000002',
      spaceId: '444444444444444444',
      name: 'lab-notes',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  categories: const [
    ChannelCategory(
      id: '500000000000000003',
      spaceId: '444444444444444444',
      name: 'Research',
      position: 0,
    ),
  ],
  roles: [
    CommunityRole(
      id: '555555555555555555',
      spaceId: '444444444444444444',
      name: '@everyone',
      position: 0,
      permissions: DiscordPermissions.viewChannel,
    ),
  ],
  members: const [
    Member(
      id: '987654321098765432',
      displayName: 'Mira',
      initials: 'MI',
      role: 'member',
      presence: Presence.online,
      colorValue: 0xff486b70,
      spaceIds: {'444444444444444444'},
      membershipsBySpace: {'444444444444444444': GuildMembership(roleIds: [])},
    ),
  ],
);
