import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

const _guildId = '200000000000000001';
const _mentionedId = '100000000000000003';

/// Somebody a message mentions belongs to the space the message is in, so
/// autocomplete in another server does not offer them.
void main() {
  final mapper = DiscordMapper();

  List<Set<String>> spacesOfMentions(Map<String, Object?> payload) => [
    for (final member in mapper.mentionedMembers(payload)) member.spaceIds,
  ];

  test('a guild mention without its member is in that guild', () {
    expect(
      spacesOfMentions({
        'guild_id': _guildId,
        'mentions': [
          {'id': _mentionedId, 'username': 'mira'},
        ],
      }),
      [
        {_guildId},
      ],
    );
  });

  test('a mention in a direct message is in the direct messages', () {
    expect(
      spacesOfMentions({
        'mentions': [
          {'id': _mentionedId, 'username': 'mira'},
        ],
      }),
      [
        {DiscordMapper.directMessagesSpaceId},
      ],
    );
  });
}
