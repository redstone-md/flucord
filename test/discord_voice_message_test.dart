import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('maps documented voice-message metadata and partial updates', () {
    final waveform = base64Encode(const [0, 64, 128, 255]);
    final mapper = DiscordMapper();
    final original = mapper.message({
      'id': 'voice-1',
      'channel_id': 'channel-1',
      'author': {'id': 'bot-1'},
      'content': '',
      'timestamp': '2026-07-24T08:00:00Z',
      'flags': DiscordMessageFlag.voiceMessage.bit,
      'attachments': [
        {
          'id': 'audio-1',
          'filename': 'voice-message.ogg',
          'url': 'https://cdn.discordapp.com/voice-message.ogg',
          'size': 4096,
          'content_type': 'audio/ogg',
          'duration_secs': 12.75,
          'waveform': waveform,
        },
      ],
    });

    expect(original.isVoiceMessage, isTrue);
    expect(original.canEdit, isFalse);
    expect(original.attachments.single.isAudio, isTrue);
    expect(
      original.attachments.single.duration,
      const Duration(milliseconds: 12750),
    );
    expect(original.attachments.single.waveform, waveform);

    final partial = mapper.message({
      'id': 'voice-1',
      'channel_id': 'channel-1',
      'pinned': true,
    }, fallback: original);
    expect(partial.isVoiceMessage, isTrue);
    expect(partial.attachments.single.durationSecs, 12.75);
    expect(partial.attachments.single.waveform, waveform);
  });
}
