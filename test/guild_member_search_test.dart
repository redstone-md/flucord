import 'package:flucord/src/data/discord/discord_desktop_gateway_protocol.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the request', () {
    test('opcode 8 names the guild and what is being typed', () {
      final frame = _protocol().requestGuildMembers(
        guildId: 'guild-1',
        query: 'mir',
      );

      expect(frame.opcode, 8);
      expect(frame.data, {
        'guild_id': 'guild-1',
        'query': 'mir',
        'limit': 25,
        'presences': true,
      });
    });

    test('the limit is kept inside what Discord will answer', () {
      final protocol = _protocol();

      // Zero would mean "everybody", which on a large guild is a request
      // nobody meant to make by typing an at-sign.
      expect(
        (protocol.requestGuildMembers(guildId: 'g', query: 'a', limit: 0).data!
            as Map<String, Object?>)['limit'],
        1,
      );
      expect(
        (protocol
                .requestGuildMembers(guildId: 'g', query: 'a', limit: 500)
                .data!
            as Map<String, Object?>)['limit'],
        100,
      );
    });
  });

  group('the answer', () {
    test('a chunk makes its members mentionable', () {
      final members = DiscordMapper().membersFromChunk({
        'guild_id': 'guild-1',
        'members': [
          {
            'user': {'id': 'user-1', 'username': 'mira', 'global_name': 'Mira'},
          },
          {
            'user': {'id': 'user-2', 'username': 'lena'},
            'nick': 'Forge Lena',
          },
          // A row with nobody in it names nobody to mention.
          {'nick': 'ghost'},
          {
            'user': {'username': 'no id'},
          },
          'nonsense',
        ],
      });

      expect(members.map((member) => member.id), ['user-1', 'user-2']);
      expect(members.first.displayName, 'Mira');
      // The guild nickname wins: it is the name everybody there sees.
      expect(members.last.displayName, 'Forge Lena');
      // Each one is filed under the guild the chunk named, so the mention list
      // for that guild can find them.
      expect(members.first.spaceIds, {'guild-1'});
    });

    test('a nickname Discord sent empty does not blank the name', () {
      final members = DiscordMapper().membersFromChunk({
        'guild_id': 'guild-1',
        'members': [
          {
            'user': {'id': 'user-1', 'username': 'mira'},
            'nick': '',
          },
        ],
      });

      expect(members.single.displayName, 'mira');
    });

    test('a chunk about no guild, or with no members, is nothing', () {
      final mapper = DiscordMapper();

      expect(mapper.membersFromChunk(const {}), isEmpty);
      expect(
        mapper.membersFromChunk(const {'guild_id': '', 'members': []}),
        isEmpty,
      );
      expect(
        mapper.membersFromChunk(const {
          'guild_id': 'guild-1',
          'members': 'nonsense',
        }),
        isEmpty,
      );
    });
  });
}

DiscordDesktopGatewayProtocol _protocol() => DiscordDesktopGatewayProtocol(
  token: 'secret-value',
  properties: const {'os': 'Windows'},
  profile: DiscordDesktopProtocolProfile.installedStable20260725,
);
