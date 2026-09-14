import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('maps message type and reference with partial-update fallback', () {
    final mapper = DiscordMapper();
    final pinned = mapper.message({
      'id': 'system-1',
      'channel_id': 'channel-1',
      'author': {'id': 'user-1'},
      'content': '',
      'timestamp': '2026-07-24T06:00:00Z',
      'type': 6,
      'message_reference': {
        'message_id': 'message-1',
        'channel_id': 'channel-1',
      },
    });

    expect(pinned.type, DiscordMessageType.channelPinnedMessage);
    expect(pinned.isSystem, isTrue);
    expect(pinned.reference?.messageId, 'message-1');

    final partial = mapper.message({
      'id': 'system-1',
      'channel_id': 'channel-1',
      'edited_timestamp': null,
    }, fallback: pinned);
    expect(partial.type, DiscordMessageType.channelPinnedMessage);
    expect(partial.reference?.messageId, 'message-1');

    final reply = mapper.message({
      'id': 'reply-1',
      'channel_id': 'channel-1',
      'author': {'id': 'user-1'},
      'content': 'Normal reply',
      'timestamp': '2026-07-24T06:01:00Z',
      'type': 19,
    });
    expect(reply.type, DiscordMessageType.reply);
    expect(reply.isSystem, isFalse);
    expect(DiscordMessageType.fromDiscordValue(999).isSystem, isFalse);
  });
}
