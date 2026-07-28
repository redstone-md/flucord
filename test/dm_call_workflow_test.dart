import 'dart:async';
import 'package:flucord/src/domain/user_profile.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/guild_management_repository.dart';
import 'package:flucord/src/domain/moderation_repository.dart';
import 'package:flucord/src/domain/message_search_repository.dart';
import 'package:flucord/src/domain/presence_repository.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';

const _call = ValueKey('toggle-call');
const _room = ValueKey('voice-surface-room');
const _chat = ValueKey('voice-surface-chat');

void main() {
  testWidgets('places a DM call and swaps the timeline for the room', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _CallableRepository();
    addTearDown(repository.dispose);

    await _openDirectMessage(tester, repository);

    // A DM offers a call; a guild text channel does not.
    expect(find.byKey(_call), findsOneWidget);
    expect(find.byTooltip('Start call'), findsOneWidget);
    expect(find.byKey(_room), findsNothing);
    // Opening the conversation is what subscribes to its call.
    expect(repository.calls.log, contains('watch:dm-mira'));

    await tester.tap(find.byKey(_call));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      repository.calls.log,
      containsAllInOrder(<String>[
        'ringable:dm-mira',
        'join:dm-mira',
        'ring:dm-mira',
      ]),
    );
    // The room is the existing voice room, not a second one built for calls.
    expect(find.byKey(const ValueKey('voice-mute')), findsOneWidget);
    expect(find.byKey(const ValueKey('message-composer')), findsNothing);
    expect(find.byTooltip('Leave call'), findsOneWidget);

    // A DM in a call earns the same room-or-chat switch a voice channel has.
    await tester.tap(find.byKey(_chat));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-mute')), findsNothing);

    await tester.tap(find.byKey(_room));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('voice-mute')), findsOneWidget);

    await tester.tap(find.byKey(_call));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(repository.calls.log, contains('leave:dm-mira'));
    expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    expect(find.byKey(_room), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('joins a call already running instead of ringing again', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _CallableRepository();
    addTearDown(repository.dispose);
    repository.calls.record = const DirectCall(
      channelId: 'dm-mira',
      messageId: 'call-message',
    );

    await _openDirectMessage(tester, repository);
    expect(find.byTooltip('Join call'), findsOneWidget);

    await tester.tap(find.byKey(_call));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(repository.calls.log, contains('join:dm-mira'));
    expect(repository.calls.log.where((e) => e.startsWith('ring:')), isEmpty);
    expect(find.byKey(const ValueKey('voice-mute')), findsOneWidget);
  });

  testWidgets('an incoming call reaches the user anywhere in the workspace', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _CallableRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(_app(repository));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // The user is sitting in a guild channel, nowhere near the DM.
    repository.calls.emitIncoming(
      const IncomingCall(channelId: 'dm-mira', callerId: 'mira'),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('incoming-call-card')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('incoming-call-decline')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(repository.calls.log, contains('stop:dm-mira'));
    expect(find.byKey(const ValueKey('incoming-call-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a DM call survives a compact window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(620, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _CallableRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(_app(repository));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    repository.calls.emitIncoming(
      const IncomingCall(channelId: 'dm-mira', callerId: 'mira'),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('incoming-call-card')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('incoming-call-accept')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(repository.calls.log, contains('join:dm-mira'));
    expect(tester.takeException(), isNull);
  });
}

Widget _app(_CallableRepository repository) => FlucordApp(
  initialRepository: repository,
  initialSessionMode: SessionMode.demo,
  restoreSavedSession: false,
);

Future<void> _openDirectMessage(
  WidgetTester tester,
  _CallableRepository repository,
) async {
  await tester.pumpWidget(_app(repository));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('member-row-mira')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('message-member')));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// The demo workspace with a call plane bolted on.
///
/// Calls are a capability of the transport, and the mock has none — so the only
/// way to drive the shell's call surfaces is a repository that answers
/// [directCalls] with something. Everything else is the demo workspace.
final class _CallableRepository implements ChatRepository {
  @override
  UserProfileRepository? get userProfile => _delegate.userProfile;

  final MockChatRepository _delegate = MockChatRepository();
  final _FakeCallService calls = _FakeCallService();

  @override
  Stream<ChatRepositoryEvent> get events => _delegate.events;

  @override
  VoiceSignalingService? get voiceSignaling => null;

  @override
  UserSettingsRepository? get userSettings => _delegate.userSettings;

  @override
  ReadStateRepository? get readState => _delegate.readState;

  @override
  DirectCallService? get directCalls => calls;

  @override
  GuildManagementRepository? get guildManagement => _delegate.guildManagement;

  @override
  ModerationRepository? get moderation => _delegate.moderation;

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
    await calls.close();
    await _delegate.close();
  }

  /// Fire-and-forget teardown. A widget test's teardown runs on the fake clock,
  /// where awaiting a stream controller's close never completes.
  void dispose() => unawaited(close());
}

final class _FakeCallService implements DirectCallService {
  final StreamController<VoiceCallEvent> _events = StreamController.broadcast();
  final List<String> log = [];
  DirectCall? record;
  IncomingCall? _incomingCall;

  @override
  Stream<VoiceCallEvent> get callEvents => _events.stream;

  @override
  IncomingCall? get incomingCall => _incomingCall;

  void emitIncoming(IncomingCall? call) {
    _incomingCall = call;
    _events.add(IncomingCallChangedEvent(call));
  }

  @override
  DirectCall? callFor(String channelId) =>
      record?.channelId == channelId ? record : null;

  @override
  void watchChannel(String channelId) => log.add('watch:$channelId');

  @override
  Future<bool> isRingable(String channelId) async {
    log.add('ringable:$channelId');
    return true;
  }

  @override
  Future<void> ring(String channelId, {List<String>? recipients}) async =>
      log.add('ring:$channelId');

  @override
  Future<void> stopRinging(
    String channelId, {
    List<String>? recipients,
  }) async => log.add('stop:$channelId');

  @override
  Future<void> joinCall({
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
  }) async => log.add('join:$channelId');

  @override
  Future<void> leaveCall(String channelId) async => log.add('leave:$channelId');

  Future<void> close() => _events.close();
}
