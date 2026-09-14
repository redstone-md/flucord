import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/conversation_summary.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';

void main() {
  test(
    'ChatController sends silently and toggles suppress-embed state',
    () async {
      final controller = ChatController(
        MockChatRepository(latency: Duration.zero),
      );
      addTearDown(controller.dispose);
      await controller.load();

      final sent = await controller.sendMessage(
        channelId: 'forge-general',
        body: 'Quiet release',
        suppressNotifications: true,
      );
      final quiet = controller.workspace!.messages.last;
      expect(sent, isTrue);
      expect(quiet.suppressesNotifications, isTrue);

      expect(await controller.toggleSuppressEmbeds(quiet), isTrue);
      expect(controller.workspace!.messages.last.suppressesEmbeds, isTrue);
      expect(
        await controller.toggleSuppressEmbeds(
          controller.workspace!.messages.last,
        ),
        isTrue,
      );
      expect(controller.workspace!.messages.last.suppressesEmbeds, isFalse);
    },
  );

  test(
    'the spoken-aloud command sends the flag and drops the command',
    () async {
      final controller = ChatController(
        MockChatRepository(latency: Duration.zero),
      );
      addTearDown(controller.dispose);
      await controller.load();

      final sent = await controller.sendMessage(
        channelId: 'forge-general',
        body: '/tts The release is out.',
      );

      expect(sent, isTrue);
      final spoken = controller.workspace!.messages.last;
      expect(spoken.body, 'The release is out.');
      expect(spoken.isTextToSpeech, isTrue);
    },
  );

  test('a lookalike command is not spoken and keeps its text', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();

    // `/ttsX` names no command, and a bare `/tts` carries nothing to say.
    final first = await controller.sendMessage(
      channelId: 'forge-general',
      body: '/ttsX not the command',
    );
    final second = await controller.sendMessage(
      channelId: 'forge-general',
      body: '/tts',
    );

    expect(first, isTrue);
    expect(second, isTrue);
    final messages = controller.workspace!.messages;
    expect(messages[messages.length - 1].body, '/tts');
    expect(messages[messages.length - 1].isTextToSpeech, isFalse);
    expect(messages[messages.length - 1 - 1].body, '/ttsX not the command');
    expect(messages[messages.length - 1 - 1].isTextToSpeech, isFalse);
  });

  test(
    'an account that turned the command off types it as plain text',
    () async {
      final controller = ChatController(_SettingsRepository(false));
      addTearDown(controller.dispose);
      await controller.load();

      final sent = await controller.sendMessage(
        channelId: 'forge-general',
        body: '/tts Not with the command off.',
      );

      expect(sent, isTrue);
      final message = controller.workspace!.messages.last;
      expect(message.body, '/tts Not with the command off.');
      expect(message.isTextToSpeech, isFalse);
    },
  );

  test('ChatController rejects edits for Discord voice messages', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final voiceMessage = ChatMessage(
      id: 'voice-1',
      channelId: 'forge-general',
      authorId: 'fly',
      body: '',
      sentAt: DateTime.utc(2026, 7, 24, 8),
      flags: DiscordMessageFlag.voiceMessage.bit,
    );

    expect(await controller.editMessage(voiceMessage, 'Not allowed'), isFalse);
    expect(controller.isSending, isFalse);
  });
}

/// The demo workspace with the settings store the spoken-aloud command reads,
/// so a test can speak for the account's own setting.
final class _SettingsRepository implements ChatRepository {
  _SettingsRepository(this.allowTextToSpeech)
    : _delegate = MockChatRepository(latency: Duration.zero);

  final bool allowTextToSpeech;
  final MockChatRepository _delegate;

  @override
  UserSettingsRepository? get userSettings => _Settings(allowTextToSpeech);

  @override
  ConversationSummaryRepository? get conversationSummaries => null;

  @override
  ReadStateRepository? get readState => null;

  @override
  Future<ChatWorkspace> loadWorkspace() => _delegate.loadWorkspace();

  @override
  Stream<ChatRepositoryEvent> get events => _delegate.events;

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
  Future<void> close() => _delegate.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not delegated');
}

final class _Settings implements UserSettingsRepository {
  const _Settings(this.allowTextToSpeech);

  final bool allowTextToSpeech;

  @override
  UserSettings? get current => UserSettings(
    messageDisplay: MessageDisplayPreferences(
      enableTextToSpeechCommand: allowTextToSpeech,
    ),
  );

  @override
  bool get isLoaded => true;

  @override
  Object? get lastWriteError => null;

  @override
  Stream<UserSettings> get updates => const Stream.empty();

  @override
  Future<UserSettings> load() async => current!;

  @override
  Future<void> apply(
    UserSettingsPatch patch, {
    UserSettingsSaveDelay delay = UserSettingsSaveDelay.immediate,
  }) async {}

  @override
  Future<void> flush() async {}
}
