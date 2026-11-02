import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/voice_message_recorder.dart';

// The composer holds the next send until slowmode ends, counted from
// `lastSentAt`. Every kind of message starts that clock, not only text. The
// desktop transport sends none of these kinds, so the session harness cannot
// reach them, and this test drives the controller over the demo repository.
void main() {
  Future<ChatController> loaded() async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  test('stickers start the clock', () async {
    final chat = await loaded();

    await chat.sendStickers(
      channelId: 'forge-general',
      stickerIds: const ['forge-signal'],
    );

    expect(chat.lastSentAt('forge-general'), isNotNull);
  });

  test('a poll starts the clock', () async {
    final chat = await loaded();

    await chat.createPoll(
      channelId: 'forge-general',
      poll: PendingPoll(
        question: 'Which build ships?',
        answers: const ['Stable', 'Canary'],
        durationHours: 24,
        allowMultiselect: false,
      ),
    );

    expect(chat.lastSentAt('forge-general'), isNotNull);
  });

  test('a voice message starts the clock', () async {
    final chat = await loaded();

    await chat.sendVoiceMessage(
      channelId: 'forge-general',
      voiceMessage: PendingVoiceMessage(
        name: 'voice.ogg',
        path: r'C:\Temp\voice.ogg',
        size: 2048,
        durationSecs: 2.4,
        waveform: 'AECA/w==',
      ),
    );

    expect(chat.lastSentAt('forge-general'), isNotNull);
  });

  test('a forward starts the clock in the channel it went to', () async {
    final chat = await loaded();
    final source = chat.workspace!.messages.firstWhere(
      (message) => message.id == 'm4',
    );

    await chat.forwardMessage(source, 'forge-native');

    expect(chat.lastSentAt('forge-native'), isNotNull);
    expect(chat.lastSentAt(source.channelId), isNull);
  });
}
