import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_cdn.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('maps documented sticker items and CDN formats', () {
    final mapper = DiscordMapper();
    final message = mapper.message(_messagePayload());

    expect(message.stickers, hasLength(3));
    expect(message.stickers[0].format, StickerFormat.png);
    expect(message.stickers[0].url, endsWith('/stickers/sticker-png.png'));
    expect(message.stickers[1].format, StickerFormat.lottie);
    expect(message.stickers[1].url, endsWith('/stickers/sticker-json.json'));
    expect(message.stickers[2].format, StickerFormat.gif);
    expect(message.stickers[2].url, endsWith('/stickers/sticker-gif.gif'));
    expect(
      DiscordCdn.sticker('sticker-apng', StickerFormat.apng),
      endsWith('/stickers/sticker-apng.png'),
    );
  });

  test(
    'preserves stickers on partial updates and accepts explicit clearing',
    () {
      final mapper = DiscordMapper();
      final original = mapper.message(_messagePayload());

      final preserved = mapper.message(const {
        'id': 'message-1',
        'content': 'edited',
      }, fallback: original);
      final cleared = mapper.message(const {
        'id': 'message-1',
        'sticker_items': <Object?>[],
      }, fallback: original);

      expect(preserved.stickers, hasLength(3));
      expect(cleared.stickers, isEmpty);
    },
  );
}

Map<String, Object?> _messagePayload() => {
  'id': 'message-1',
  'channel_id': 'channel-1',
  'author': {'id': 'user-1'},
  'content': '',
  'timestamp': '2026-07-23T03:47:00Z',
  'attachments': const [],
  'embeds': const [],
  'reactions': const [],
  'sticker_items': const [
    {'id': 'sticker-png', 'name': 'Signal', 'format_type': 1},
    {'id': 'sticker-json', 'name': 'Relay', 'format_type': 3},
    {'id': 'sticker-gif', 'name': 'Deploy', 'format_type': 4},
  ],
};
