import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('SQLite retains voice-message duration and waveform metadata', () async {
    final cache = await SqliteChatCache.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(cache.close);
    final waveform = base64Encode(const [12, 48, 96, 192]);
    final message = ChatMessage(
      id: 'voice-1',
      channelId: 'channel-1',
      authorId: 'bot-1',
      body: '',
      sentAt: DateTime.utc(2026, 7, 24, 8),
      flags: DiscordMessageFlag.voiceMessage.bit,
      attachments: [
        MessageAttachment(
          id: 'audio-1',
          fileName: 'voice-message.ogg',
          url: 'https://cdn.discordapp.com/voice-message.ogg',
          size: 4096,
          contentType: 'audio/ogg',
          durationSecs: 8.4,
          waveform: waveform,
        ),
      ],
    );

    await cache.writeMessage(message);
    final restored = await cache.readMessage(message.id);

    expect(restored?.isVoiceMessage, isTrue);
    expect(restored?.attachments.single.durationSecs, 8.4);
    expect(restored?.attachments.single.waveform, waveform);
  });
}
