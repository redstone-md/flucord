import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';

void main() {
  test('sends catalog stickers and rejects invalid selections', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(
      await controller.sendStickers(
        channelId: 'forge-general',
        stickerIds: const ['forge-signal', 'forge-relay'],
      ),
      isTrue,
    );
    final message = controller.workspace!.messages.last;
    expect(message.body, isEmpty);
    expect(message.stickers.map((sticker) => sticker.name), [
      'Native signal',
      'Relay click',
    ]);

    expect(
      await controller.sendStickers(
        channelId: 'forge-general',
        stickerIds: const ['missing'],
      ),
      isFalse,
    );
    expect(
      await controller.sendStickers(
        channelId: 'forge-general',
        stickerIds: const ['forge-signal', 'forge-signal'],
      ),
      isTrue,
    );
    expect(controller.workspace!.messages.last.stickers, hasLength(1));
  });

  test('accepts the timeline a voice channel carries', () async {
    final controller = ChatController(
      MockChatRepository(latency: Duration.zero),
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(
      await controller.sendStickers(
        channelId: 'forge-voice',
        stickerIds: const ['forge-signal'],
      ),
      isTrue,
    );
    expect(
      await controller.sendStickers(
        channelId: 'forge-forum',
        stickerIds: const ['forge-signal'],
      ),
      isFalse,
    );
    expect(
      controller.workspace!
          .messagesFor('forge-voice')
          .last
          .stickers
          .single
          .name,
      'Native signal',
    );
  });
}
