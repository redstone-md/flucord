import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_models.dart';

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
