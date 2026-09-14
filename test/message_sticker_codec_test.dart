import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/message_sticker_codec.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('round-trips immutable message sticker metadata', () {
    const stickers = [
      MessageSticker(
        id: 'sticker-1',
        name: 'Native signal',
        format: StickerFormat.apng,
        url: 'https://cdn.discordapp.com/stickers/sticker-1.png',
      ),
    ];

    final restored = MessageStickerCodec.decode(
      MessageStickerCodec.encode(stickers),
    );

    expect(restored.single.id, 'sticker-1');
    expect(restored.single.name, 'Native signal');
    expect(restored.single.format, StickerFormat.apng);
    expect(restored.single.isAnimated, isTrue);
  });

  test('ignores malformed cached sticker entries', () {
    final restored = MessageStickerCodec.decode(
      '[{"id":"missing-url","name":"Broken","format_type":1},42]',
    );

    expect(restored, isEmpty);
    expect(StickerFormat.fromDiscordValue(99), StickerFormat.unknown);
  });
}
