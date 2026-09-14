import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/app_composition.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/data/discord/discord_conversation_summary_service.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/account_connections.dart';
import 'package:flucord/src/domain/account_data_package.dart';
import 'package:flucord/src/domain/account_entitlements.dart';
import 'package:flucord/src/domain/account_standing.dart';
import 'package:flucord/src/domain/app_authorisation.dart';
import 'package:flucord/src/domain/age_verification.dart';
import 'package:flucord/src/domain/application_command.dart';
import 'package:flucord/src/domain/auth_session.dart';
import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/conversation_summary.dart';
import 'package:flucord/src/domain/desktop_relationship_repository.dart';
import 'package:flucord/src/domain/expression_favorites.dart';
import 'package:flucord/src/domain/family_centre.dart';
import 'package:flucord/src/domain/gif_picker.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/message_component.dart';
import 'package:flucord/src/domain/message_search_repository.dart';
import 'package:flucord/src/domain/moderation_repository.dart';
import 'package:flucord/src/domain/multi_factor_auth.dart';
import 'package:flucord/src/domain/game_detection.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/domain/guild_expression_repository.dart';
import 'package:flucord/src/domain/stage_channel.dart';
import 'package:flucord/src/domain/thread_membership.dart';
import 'package:flucord/src/domain/user_notes.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/message_list.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/pane_harness.dart';

/// The summaries strip above the timeline, driven over the store the
/// desktop transport already fills. The pane is pumped the way the app
/// wires it: scopes above it, the channel selected, summaries folded into
/// the store through the same dispatch that feeds a live session.
void main() {
  testWidgets('renders each summary with its topic, text and participants', (
    tester,
  ) async {
    await _pumpPane(
      tester,
      seed: (store) {
        store.accept('CONVERSATION_SUMMARY_UPDATE', _dispatch());
      },
    );

    expect(
      find.byKey(const ValueKey('conversation-summaries')),
      findsOneWidget,
    );
    expect(find.text('Release planning'), findsOneWidget);
    expect(find.text('They agreed to ship on Friday.'), findsOneWidget);
    expect(find.text('Mira Chen · Roman Vale'), findsOneWidget);
    // The timeline is still there, under the strip.
    expect(find.byType(MessageList), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a summary jumps to its starting message', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final composition = await _pumpPane(
      tester,
      seed: (store) {
        store.accept('CONVERSATION_SUMMARY_UPDATE', _dispatch());
      },
    );

    await tester.tap(find.byKey(const ValueKey('conversation-summary-s1')));
    await tester.pumpAndSettle();

    // The timeline is built around the message the summary starts at, the
    // same landing a mention from the inbox produces: the strip stays above
    // (header 58 plus strip 128) and the message sits in the upper part of
    // the timeline rather than wherever the reader was.
    expect(composition.workspace.targetMessageId, 'm1');
    final start = find.byKey(const ValueKey('message-m1'));
    expect(start, findsOneWidget);
    expect(tester.getTopLeft(start).dy, inInclusiveRange(186, 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a channel without summaries renders no strip', (tester) async {
    await _pumpPane(tester);

    expect(find.byKey(const ValueKey('conversation-summaries')), findsNothing);
    expect(find.byType(MessageList), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a summary arriving mid-conversation appears above the timeline',
    (tester) async {
      final repository = _SummariesRepository();
      await _pumpPane(tester, repository: repository);

      expect(
        find.byKey(const ValueKey('conversation-summaries')),
        findsNothing,
      );

      repository.summaries.accept('CONVERSATION_SUMMARY_UPDATE', _dispatch());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('conversation-summaries')),
        findsOneWidget,
      );
      expect(find.text('Release planning'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Map<String, Object?> _dispatch() => {
  'channel_id': 'forge-general',
  'summaries': [
    {
      'id': 's1',
      'topic': 'Release planning',
      'summ_short': 'They agreed to ship on Friday.',
      'people': const ['mira', 'roman'],
      'start_id': 'm1',
      'end_id': 'm3',
      'count': 12,
    },
  ],
};

/// Builds the composition the app builds, with a repository that answers the
/// summaries capability the way the desktop transport does, then pumps the
/// pane on the seeded channel. [seed] folds dispatches in before the pane is
/// built, so a test can start with summaries already on screen.
Future<AppComposition> _pumpPane(
  WidgetTester tester, {
  _SummariesRepository? repository,
  void Function(DiscordConversationSummaryService store)? seed,
}) async {
  final repo = repository ?? _SummariesRepository();
  final composition = AppComposition(
    AppBootstrap(initialRepository: repo, initialSessionMode: SessionMode.demo),
  );
  addTearDown(composition.dispose);
  addTearDown(repo.dispose);
  seed?.call(repo.summaries);
  final workspace = await repo.loadWorkspace();
  composition.workspace
    ..reconcile(workspace)
    ..selectChannel('forge-general');
  await composition.chat.load();

  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: paneHarness(
          composition,
          workspace,
          channel: workspace.channelById('forge-general'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return composition;
}

/// The demo workspace with the real summaries store bolted on, the same way
/// the call tests bolt their plane onto the mock. The store is the one the
/// desktop transport uses, so the strip reads exactly what a live session
/// would hand it.
final class _SummariesRepository implements ChatRepository {
  final MockChatRepository _delegate = MockChatRepository(
    latency: Duration.zero,
  );
  final DiscordConversationSummaryService summaries =
      DiscordConversationSummaryService();

  @override
  ConversationSummaryRepository? get conversationSummaries => summaries;
  @override
  AccountConnectionsRepository? get accountConnections => null;

  @override
  AccountEntitlementsRepository? get accountEntitlements => null;

  @override
  AppAuthorisationRepository? get appAuthorisation => null;
  @override
  UserNotesRepository? get userNotes => null;

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
  GuildExpressionRepository? get expressions => _delegate.expressions;

  @override
  GifRepository? get gifs => _delegate.gifs;

  @override
  ExpressionFavoritesRepository? get expressionFavorites =>
      _delegate.expressionFavorites;

  @override
  ApplicationCommandRepository? get applicationCommands =>
      _delegate.applicationCommands;

  @override
  MessageComponentRepository? get messageComponents =>
      _delegate.messageComponents;

  @override
  GoLiveRepository? get goLive => _delegate.goLive;

  @override
  Stream<ChatRepositoryEvent> get events => _delegate.events;

  @override
  VoiceSignalingService? get voiceSignaling => null;

  @override
  UserSettingsRepository? get userSettings => _delegate.userSettings;

  @override
  ReadStateRepository? get readState => _delegate.readState;

  @override
  DirectCallService? get directCalls => null;

  @override
  GuildManagementRepository? get guildManagement => _delegate.guildManagement;

  @override
  ModerationRepository? get moderation => _delegate.moderation;

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
  AccountDataPackageRepository? get accountDataPackage => null;

  @override
  MessageSearchRepository? get messageSearch => null;

  @override
  PresenceService? get presence => null;
  @override
  DetectableGameRepository? get detectableGames => null;

  @override
  Future<ChatWorkspace> loadWorkspace() => _delegate.loadWorkspace();

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
    String? aroundMessageId,
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
    bool textToSpeech = false,
  }) => _delegate.sendMessage(
    channelId: channelId,
    authorId: authorId,
    body: body,
    attachments: attachments,
    replyToMessageId: replyToMessageId,
    suppressNotifications: suppressNotifications,
    textToSpeech: textToSpeech,
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

  @override
  Future<void> resolveAutoModAlert({
    required String guildId,
    required String channelId,
    required String messageId,
    required AutoModAlertAction action,
  }) => _delegate.resolveAutoModAlert(
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
  Future<void> close() async {
    await summaries.close();
    await _delegate.close();
  }

  /// Fire-and-forget teardown. A widget test's teardown runs on the fake
  /// clock, where awaiting a stream controller's close never completes.
  void dispose() => unawaited(close());
}
