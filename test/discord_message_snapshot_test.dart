import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flucord/src/domain/chat_models.dart';

void main() {
  test('maps documented forward snapshots with partial-update fallback', () {
    final mapper = DiscordMapper();
    final forwarded = mapper.message({
      'id': 'forward-1',
      'channel_id': 'target-channel',
      'author': {'id': 'bot-1'},
      'content': '',
      'timestamp': '2026-07-24T08:00:00Z',
      'type': 0,
      'message_reference': {
        'type': 1,
        'message_id': 'source-1',
        'channel_id': 'source-channel',
        'guild_id': 'guild-1',
      },
      'message_snapshots': [
        {
          'message': {
            'type': 19,
            'content': 'Original release notes',
            'timestamp': '2026-07-23T18:00:00Z',
            'edited_timestamp': '2026-07-23T18:05:00Z',
            'flags': 16384,
            'attachments': [
              {
                'id': 'attachment-1',
                'filename': 'notes.txt',
                'url': 'https://cdn.discordapp.com/notes.txt',
                'size': 42,
                'duration_secs': 4.25,
                'waveform': 'AECA/w==',
              },
            ],
            'embeds': [
              {'title': 'Release', 'description': 'Ready'},
            ],
            'sticker_items': [
              {'id': 'sticker-1', 'name': 'Ship', 'format_type': 1},
            ],
            'mentions': [
              {'id': 'user-1'},
            ],
            'mention_roles': ['role-1'],
            'components': [
              {'type': 1, 'components': []},
            ],
          },
        },
      ],
    });

    expect(forwarded.isForwarded, isTrue);
    expect(forwarded.reference?.type, DiscordMessageReferenceType.forward);
    expect(forwarded.reference?.guildId, 'guild-1');
    final snapshot = forwarded.snapshots.single;
    expect(snapshot.type, DiscordMessageType.reply);
    expect(snapshot.body, 'Original release notes');
    expect(snapshot.editedAt, isNotNull);
    expect(snapshot.flags, 16384);
    expect(snapshot.attachments.single.fileName, 'notes.txt');
    expect(snapshot.attachments.single.durationSecs, 4.25);
    expect(snapshot.attachments.single.waveform, 'AECA/w==');
    expect(snapshot.embeds.single.title, 'Release');
    expect(snapshot.stickers.single.name, 'Ship');
    expect(snapshot.mentionedUserIds, {'user-1'});
    expect(snapshot.mentionedRoleIds, {'role-1'});
    expect(snapshot.components.single.payloadJson, contains('"type":1'));

    final partial = mapper.message({
      'id': 'forward-1',
      'channel_id': 'target-channel',
      'edited_timestamp': null,
    }, fallback: forwarded);
    expect(partial.reference?.type, DiscordMessageReferenceType.forward);
    expect(partial.snapshots.single.body, 'Original release notes');
  });
}
