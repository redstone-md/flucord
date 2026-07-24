import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';

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
}
