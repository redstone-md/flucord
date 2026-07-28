import 'dart:async';
import 'package:flucord/src/domain/application_command.dart';
import 'package:flucord/src/domain/gif_picker.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/domain/stage_channel.dart';
import 'package:flucord/src/domain/thread_membership.dart';
import 'package:flucord/src/domain/user_profile.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/message_search.dart';
import 'package:flucord/src/domain/message_search_repository.dart';
import 'package:flucord/src/domain/moderation_repository.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';

const _searchField = ValueKey('message-search');
const _panel = ValueKey('message-search-panel');

void main() {
  testWidgets('searches the server from the header and jumps to a hit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _SearchableRepository();
    addTearDown(repository.dispose);

    await _openWorkspace(tester, repository);

    // Typing still filters the messages already on screen.
    await tester.enterText(find.byKey(_searchField), 'continuous');
    await tester.pump();
    expect(find.byKey(_panel), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(_panel), findsOneWidget);
    expect(
      repository.search.requests.single.query.filters.content,
      'continuous',
    );
    expect(
      repository.search.requests.single.scope,
      const GuildMessageSearchScope('forge'),
    );
    expect(find.text('1 result'), findsOneWidget);
    // The hit is in a channel the timeline is not showing yet.
    expect(find.byKey(const ValueKey('message-m5')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('jump-to-m5')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-m5')), findsOneWidget);
    // The panel survives the jump, so the next hit is one tap away.
    expect(find.byKey(_panel), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('close-search-panel')));
    await tester.pumpAndSettle();
    expect(find.byKey(_panel), findsNothing);
  });

  testWidgets('a private conversation searches its own channel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _SearchableRepository();
    addTearDown(repository.dispose);

    await _openWorkspace(tester, repository);
    await tester.tap(find.byKey(const ValueKey('member-row-mira')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('message-member')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(_searchField), 'notes');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // A DM has no guild to search, so it asks about the channel itself.
    expect(
      repository.search.requests.single.scope,
      const ChannelMessageSearchScope('dm-mira'),
    );
    expect(find.byKey(_panel), findsOneWidget);
  });

  testWidgets('a transport without search never offers it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // The demo workspace is the whole corpus, so the bar filters and no more.
    await tester.enterText(find.byKey(_searchField), 'copper');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(_panel), findsNothing);
  });
}

Future<void> _openWorkspace(
  WidgetTester tester,
  ChatRepository repository,
) async {
  await tester.pumpWidget(
    FlucordApp(
      initialRepository: repository,
      initialSessionMode: SessionMode.demo,
      restoreSavedSession: false,
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// The demo workspace with a search plane bolted on.
///
/// Search is a capability of the transport and the mock has none, so the only
/// way to drive the shell's search surfaces is a repository that answers
/// [messageSearch] with something. Everything else is the demo workspace.
final class _SearchableRepository implements ChatRepository {
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

  final MockChatRepository _delegate = MockChatRepository();
  final _FakeSearchPlane search = _FakeSearchPlane();

  @override
  Stream<ChatRepositoryEvent> get events => _delegate.events;

  @override
  VoiceSignalingService? get voiceSignaling => null;

  @override
  UserSettingsRepository? get userSettings => _delegate.userSettings;

  @override
  DirectCallService? get directCalls => null;

  @override
  MessageSearchRepository? get messageSearch => search;

  // Search is the only plane bolted on; for everything else the demo workspace
  // is still the honest answer, so those questions go straight to it.
  @override
  ReadStateRepository? get readState => _delegate.readState;

  @override
  GuildManagementRepository? get guildManagement => _delegate.guildManagement;

  @override
  ModerationRepository? get moderation => _delegate.moderation;

  @override
  PresenceService? get presence => _delegate.presence;

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
  Future<void> close() => _delegate.close();

  /// Fire-and-forget teardown: a widget test's teardown runs on the fake clock,
  /// where awaiting a stream controller's close never completes.
  void dispose() => unawaited(close());
}

final class _FakeSearchPlane implements MessageSearchRepository {
  final List<MessageSearchRequest> requests = [];

  @override
  Future<MessageSearchOutcome> searchMessages(
    MessageSearchRequest request, {
    MessageSearchIndexingCallback? onIndexing,
  }) async {
    requests.add(request);
    return MessageSearchCompleted(
      MessageSearchResults(
        totalResults: 1,
        groups: [
          MessageSearchHitGroup(
            messages: [
              ChatMessage(
                id: 'm5',
                channelId: 'forge-design',
                authorId: 'mira',
                body: 'The selected path should read as one continuous signal.',
                sentAt: DateTime.utc(2024, 5),
              ),
            ],
            hitIndex: 0,
          ),
        ],
      ),
    );
  }

  @override
  void cancelSearch(MessageSearchScope scope) {}
}
