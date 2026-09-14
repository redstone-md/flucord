import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
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
import 'package:flucord/src/domain/expression_favorites.dart';
import 'package:flucord/src/domain/family_centre.dart';
import 'package:flucord/src/domain/gif_picker.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/guild_audit_log.dart';
import 'package:flucord/src/domain/guild_expression_repository.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/message_component.dart';
import 'package:flucord/src/domain/message_search_repository.dart';
import 'package:flucord/src/domain/moderation_repository.dart';
import 'package:flucord/src/domain/multi_factor_auth.dart';
import 'package:flucord/src/domain/game_detection.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/domain/stage_channel.dart';
import 'package:flucord/src/domain/thread_membership.dart';
import 'package:flucord/src/domain/user_notes.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/join_server_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resolves a pasted link to a preview with name and icon', (
    tester,
  ) async {
    final chat = await _loadedController();
    addTearDown(chat.dispose);
    await tester.pumpWidget(_app(chat));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('join-server-invite-field')),
      'https://discord.gg/aurora',
    );
    // The rebuild the text change scheduled is what enables the submit
    // button; the tap happens on the frame after it.
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('join-server-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('join-server-preview')), findsOneWidget);
    expect(find.text('Aurora Labs'), findsOneWidget);
    expect(find.text('1204 members'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('join-server-preview-icon')),
      findsOneWidget,
    );
  });

  testWidgets('an already-joined invite says so and keeps Join disabled', (
    tester,
  ) async {
    final chat = await _loadedController(
      preview: const InvitePreview(
        code: 'aurora',
        name: 'The Forge',
        guildId: 'forge',
      ),
    );
    addTearDown(chat.dispose);

    await tester.pumpWidget(_app(chat));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('join-server-invite-field')),
      'aurora',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('join-server-submit')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('join-server-already-joined')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('join-server-submit')),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('a refused preview shows the refusal message', (tester) async {
    final chat = await _loadedController(
      previewRefusal: const GuildAccessException(
        refusal: GuildAccessRefusal.expired,
        message: 'This invite has expired.',
      ),
    );
    addTearDown(chat.dispose);

    await tester.pumpWidget(_app(chat));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('join-server-invite-field')),
      'aurora',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('join-server-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('join-server-error')), findsOneWidget);
    expect(find.text('This invite has expired.'), findsOneWidget);
  });

  testWidgets('a join lands the dialog result on the caller', (tester) async {
    final chat = await _loadedController();
    addTearDown(chat.dispose);

    String? joined;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                joined = await showJoinServerDialog(context, chat: chat);
              },
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('join-server-invite-field')),
      'aurora',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('join-server-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('join-server-submit')));
    await tester.pumpAndSettle();

    expect(joined, 'aurora-space');
    // The workspace folded the server in: the dialog answered what the rail
    // now shows.
    expect(chat.workspace!.spaceOrNull('aurora-space'), isNotNull);
  });
}

Widget _app(ChatController chat) => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(
    body: Builder(
      builder: (context) => FilledButton(
        onPressed: () => showJoinServerDialog(context, chat: chat),
        child: const Icon(Icons.add),
      ),
    ),
  ),
);

/// A controller over the demo workspace, with a fake access plane layered on
/// the join surface through the controller's contract. The demo repository
/// has no server-access plane, so the preview and join answers come from the
/// test's own subclass.
Future<ChatController> _loadedController({
  InvitePreview? preview,
  GuildAccessException? previewRefusal,
}) async {
  final repository = _PreviewingRepository(
    preview: preview,
    previewRefusal: previewRefusal,
  );
  final controller = ChatController(repository);
  await controller.load();
  return controller;
}

/// The demo transport with a server-access plane layered over it: the
/// repository answers the demo workspace, and the plane answers the join
/// surface. Composition, because the demo repository is final and has no
/// account behind it to join with.
final class _PreviewingRepository implements ChatRepository {
  _PreviewingRepository({this.preview, this.previewRefusal})
    : _demo = MockChatRepository(latency: Duration.zero);

  final MockChatRepository _demo;
  final InvitePreview? preview;
  final GuildAccessException? previewRefusal;

  @override
  GuildManagementRepository? get guildManagement => _plane;

  @override
  AccountConnectionsRepository? get accountConnections =>
      _demo.accountConnections;

  @override
  AccountEntitlementsRepository? get accountEntitlements =>
      _demo.accountEntitlements;

  @override
  AppAuthorisationRepository? get appAuthorisation => _demo.appAuthorisation;

  @override
  UserNotesRepository? get userNotes => _demo.userNotes;

  @override
  AccountDataPackageRepository? get accountDataPackage =>
      _demo.accountDataPackage;

  @override
  GuildExpressionRepository? get expressions => _demo.expressions;

  late final _PreviewingGuildManagement _plane = _PreviewingGuildManagement(
    preview: preview,
    previewRefusal: previewRefusal,
  );

  @override
  Stream<ChatRepositoryEvent> get events => _demo.events;

  @override
  Future<ChatWorkspace> loadWorkspace() => _demo.loadWorkspace();

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
    String? aroundMessageId,
  }) => _demo.loadChannelHistory(
    channelId,
    beforeMessageId: beforeMessageId,
    aroundMessageId: aroundMessageId,
  );

  @override
  Future<ChannelHistory> loadPinnedMessages(String channelId) =>
      _demo.loadPinnedMessages(channelId);

  @override
  Future<void> close() => _demo.close();

  // Everything this test does not drive keeps the demo repository's honest
  // refusal, by delegation where the demo has one and a null where it has
  // none.
  @override
  Future<ChatMessage> sendMessage({
    required String channelId,
    required String authorId,
    required String body,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
    bool textToSpeech = false,
  }) => _demo.sendMessage(
    channelId: channelId,
    authorId: authorId,
    body: body,
    attachments: attachments,
    replyToMessageId: replyToMessageId,
    suppressNotifications: suppressNotifications,
    textToSpeech: textToSpeech,
  );

  @override
  Future<void> startTyping(String channelId) => _demo.startTyping(channelId);

  @override
  Future<void> saveChannelActivity(ConversationChannel channel) =>
      _demo.saveChannelActivity(channel);

  @override
  VoiceSignalingService? get voiceSignaling => _demo.voiceSignaling;

  @override
  UserProfileRepository? get userProfile => _demo.userProfile;

  @override
  ThreadMembershipRepository? get threadMembership => _demo.threadMembership;

  @override
  StageRepository? get stages => _demo.stages;

  @override
  SoundboardRepository? get soundboard => _demo.soundboard;

  @override
  GifRepository? get gifs => _demo.gifs;

  @override
  ExpressionFavoritesRepository? get expressionFavorites =>
      _demo.expressionFavorites;

  @override
  ApplicationCommandRepository? get applicationCommands =>
      _demo.applicationCommands;

  @override
  MessageComponentRepository? get messageComponents => _demo.messageComponents;

  @override
  GoLiveRepository? get goLive => _demo.goLive;

  @override
  ConversationSummaryRepository? get conversationSummaries =>
      _demo.conversationSummaries;

  @override
  UserSettingsRepository? get userSettings => _demo.userSettings;

  @override
  ReadStateRepository? get readState => _demo.readState;

  @override
  DirectCallService? get directCalls => _demo.directCalls;

  @override
  ModerationRepository? get moderation => _demo.moderation;

  @override
  SafetyHubRepository? get safetyHub => _demo.safetyHub;

  @override
  FamilyCentreRepository? get familyCentre => _demo.familyCentre;

  @override
  AuthSessionRepository? get authSessions => _demo.authSessions;

  @override
  MultiFactorAuthRepository? get multiFactorAuth => _demo.multiFactorAuth;

  @override
  AgeVerificationRepository? get ageVerification => _demo.ageVerification;

  @override
  DesktopRelationshipRepository? get relationships => _demo.relationships;

  @override
  MessageSearchRepository? get messageSearch => _demo.messageSearch;

  @override
  PresenceService? get presence => _demo.presence;

  @override
  DetectableGameRepository? get detectableGames => null;

  @override
  Future<DirectConversation> openDirectConversation(String recipientId) =>
      _demo.openDirectConversation(recipientId);

  @override
  Future<ConversationChannel> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) => _demo.createThreadFromMessage(
    channelId: channelId,
    messageId: messageId,
    name: name,
    autoArchiveDurationMinutes: autoArchiveDurationMinutes,
  );

  @override
  Future<ChatMessage> editMessage({
    required String channelId,
    required String messageId,
    required String body,
  }) =>
      _demo.editMessage(channelId: channelId, messageId: messageId, body: body);

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) => _demo.deleteMessage(channelId: channelId, messageId: messageId);

  @override
  Future<void> resolveAutoModAlert({
    required String guildId,
    required String channelId,
    required String messageId,
    required AutoModAlertAction action,
  }) => _demo.resolveAutoModAlert(
    guildId: guildId,
    channelId: channelId,
    messageId: messageId,
    action: action,
  );

  @override
  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _demo.addReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );

  @override
  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _demo.removeReaction(
    channelId: channelId,
    messageId: messageId,
    emoji: emoji,
  );

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) => _demo.pinMessage(channelId: channelId, messageId: messageId);

  @override
  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) => _demo.unpinMessage(channelId: channelId, messageId: messageId);
}

/// The join surface's answers, in memory. The settings routes stay
/// unimplemented for the same reason as in the controller test.
final class _PreviewingGuildManagement implements GuildManagementRepository {
  _PreviewingGuildManagement({this.preview, this.previewRefusal});

  final InvitePreview? preview;
  final GuildAccessException? previewRefusal;

  @override
  Future<InvitePreview> previewInvite(String code) async {
    final refusal = previewRefusal;
    if (refusal != null) throw refusal;
    return preview ??
        const InvitePreview(
          code: 'aurora',
          name: 'Aurora Labs',
          guildId: 'aurora-space',
          approximateMemberCount: 1204,
        );
  }

  @override
  Future<JoinedGuild> joinGuild(String code) async => const JoinedGuild(
    space: CommunitySpace(
      id: 'aurora-space',
      name: 'Aurora Labs',
      monogram: 'AL',
      colorValue: 0xff486b70,
    ),
    channels: [],
    categories: [],
    roles: [],
  );

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

  @override
  Future<void> leaveGuild(String guildId) => throw UnimplementedError();

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
  Future<JoinedGuild> createGuild({required String name}) =>
      throw UnimplementedError();
}
