import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/voice_message_recorder.dart';

void main() {
  test(
    'sends a pending voice message through the controller boundary',
    () async {
      final controller = ChatController(
        MockChatRepository(latency: Duration.zero),
      );
      addTearDown(controller.dispose);
      await controller.load();

      final sent = await controller.sendVoiceMessage(
        channelId: 'forge-general',
        voiceMessage: PendingVoiceMessage(
          name: 'voice.ogg',
          path: r'C:\Temp\voice.ogg',
          size: 2048,
          durationSecs: 2.4,
          waveform: 'AECA/w==',
        ),
      );

      final message = controller.workspace!.messages.last;
      expect(sent, isTrue);
      expect(message.isVoiceMessage, isTrue);
      expect(message.body, isEmpty);
      expect(message.attachments.single.durationSecs, 2.4);
      expect(message.attachments.single.waveform, 'AECA/w==');
    },
  );
}
