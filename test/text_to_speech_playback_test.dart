import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/text_to_speech_playback_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/conversation_summary.dart';
import 'package:flucord/src/domain/message_speech.dart';
import 'package:flucord/src/domain/read_state_repository.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';

/// The playback half of text-to-speech: what a user hears when a spoken-aloud
/// message arrives, driven over the same incoming-message stream the app
/// subscribes to, with a fake standing in for the speaker.
void main() {
  test(
    'speaks a spoken-aloud message that lands in the channel being read',
    () async {
      final harness = _PlaybackHarness();
      await harness.load();
      addTearDown(harness.dispose);

      await harness.emitSpokenMessage(body: 'The release is out.');
      await harness.settle();

      expect(harness.speech.spoken, ['The release is out.']);
    },
  );

  test('a plain message, or an unspoken one, is not spoken', () async {
    final harness = _PlaybackHarness();
    await harness.load();
    addTearDown(harness.dispose);

    await harness.emitMessage(body: 'Plain text.');
    await harness.emitSpokenMessage(body: 'Wrongly flagged.', spoken: false);
    await harness.settle();

    expect(harness.speech.spoken, isEmpty);
  });

  test('a spoken-aloud message in another channel stays quiet', () async {
    final harness = _PlaybackHarness();
    await harness.load();
    addTearDown(harness.dispose);

    await harness.emitSpokenMessage(body: 'Not here.', channelId: 'forge-off');
    await harness.settle();

    expect(harness.speech.spoken, isEmpty);
  });

  test('an account that turned the setting off hears nothing', () async {
    final harness = _PlaybackHarness();
    await harness.load();
    addTearDown(harness.dispose);

    harness.settings.allowTextToSpeech = false;
    await harness.emitSpokenMessage(body: 'Not with the setting off.');
    await harness.settle();

    expect(harness.speech.spoken, isEmpty);
  });

  test('this account\'s own spoken message is not echoed', () async {
    final harness = _PlaybackHarness();
    await harness.load();
    addTearDown(harness.dispose);

    await harness.emitSpokenMessage(
      body: 'My own words.',
      authorId: harness.chat.workspace!.currentMemberId,
    );
    await harness.settle();

    expect(harness.speech.spoken, isEmpty);
  });

  test(
    'a machine with no speech player leaves the message on screen',
    () async {
      final harness = _PlaybackHarness(player: null);
      await harness.load();
      addTearDown(harness.dispose);

      await harness.emitSpokenMessage(body: 'Nothing to say it with.');
      await harness.settle();

      // The message still arrived; only the speech is absent.
      expect(
        harness.chat.workspace!.messages.any(
          (message) => message.body == 'Nothing to say it with.',
        ),
        isTrue,
      );
      expect(harness.playback.lastSpoken, 'Nothing to say it with.');
    },
  );
}

final class _PlaybackHarness {
  _PlaybackHarness({MessageSpeechPlayer? player})
    : speech = _RecordingSpeech() {
    settings = _SettingsStore();
    repository = _SpokenRepository(settings);
    chat = ChatController(repository);
    playback = TextToSpeechPlaybackController(
      chat: chat,
      player: player ?? speech,
    );
  }

  final _RecordingSpeech speech;
  late final _SettingsStore settings;
  late final _SpokenRepository repository;
  late final ChatController chat;
  late final TextToSpeechPlaybackController playback;

  Future<void> load() async {
    await chat.load();
    await chat.openChannel('forge-general');
  }

  Future<void> emitSpokenMessage({
    required String body,
    String channelId = 'forge-general',
    String authorId = 'ember',
    bool spoken = true,
  }) => emitMessage(
    body: body,
    channelId: channelId,
    authorId: authorId,
    textToSpeech: spoken,
  );

  Future<void> emitMessage({
    required String body,
    String channelId = 'forge-general',
    String authorId = 'ember',
    bool textToSpeech = false,
  }) async {
    final message = ChatMessage(
      id: 'arriving-${repository.sequence++}',
      channelId: channelId,
      authorId: authorId,
      body: body,
      sentAt: DateTime.now(),
      isTextToSpeech: textToSpeech,
    );
    repository.emit(MessageUpsertedEvent(message: message, isNew: true));
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> dispose() async {
    playback.dispose();
    chat.dispose();
    await repository.close();
  }
}

final class _RecordingSpeech implements MessageSpeechPlayer {
  final List<String> spoken = [];

  @override
  bool get isSupported => true;

  @override
  Future<bool> speak(String text) async {
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stop() async {}
}

/// Settings the test can flip between one message and the next, which is how
/// the controller must read them.
final class _SettingsStore implements UserSettingsRepository {
  bool allowTextToSpeech = true;

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

/// The demo workspace with a settings store and a live event stream, which is
/// everything the playback half listens to. Everything the controller touches
/// on a plain session is delegated; anything else is a mistake in the test.
final class _SpokenRepository implements ChatRepository {
  _SpokenRepository(this.settings)
    : _delegate = MockChatRepository(latency: Duration.zero);

  final _SettingsStore settings;
  final MockChatRepository _delegate;
  final StreamController<ChatRepositoryEvent> _arrivals =
      StreamController.broadcast();

  int sequence = 0;

  void emit(ChatRepositoryEvent event) => _arrivals.add(event);

  @override
  Stream<ChatRepositoryEvent> get events {
    if (!_piped) {
      _piped = true;
      _delegate.events.listen(_arrivals.add);
    }
    return _arrivals.stream;
  }

  bool _piped = false;

  @override
  UserSettingsRepository? get userSettings => settings;

  @override
  ConversationSummaryRepository? get conversationSummaries => null;

  @override
  ReadStateRepository? get readState => null;

  @override
  Future<ChatWorkspace> loadWorkspace() => _delegate.loadWorkspace();

  @override
  Future<ChannelHistoryPage> loadChannelHistory(
    String channelId, {
    String? beforeMessageId,
    String? aroundMessageId,
  }) => _delegate.loadChannelHistory(
    channelId,
    beforeMessageId: beforeMessageId,
    aroundMessageId: aroundMessageId,
  );

  @override
  Future<void> close() async {
    await _arrivals.close();
    await _delegate.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} was not delegated');
}
