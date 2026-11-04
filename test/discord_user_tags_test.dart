import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

const _guild = '200000000000000001';
const _clanGuild = '200000000000000009';

Map<String, Object?> _user({
  String id = '100000000000000002',
  bool? bot,
  Map<String, Object?>? primaryGuild,
}) => {
  'id': id,
  'username': 'mira',
  'bot': ?bot,
  'primary_guild': ?primaryGuild,
};

const _clan = {
  'tag': 'CODE',
  'badge': 'badgehash',
  'identity_guild_id': _clanGuild,
  'identity_enabled': true,
};

/// A user from Discord keeps its bot flag and its clan tag, wherever the user
/// object arrives.
void main() {
  final mapper = DiscordMapper();

  test('a message author keeps the bot flag and the clan tag', () {
    final author = mapper.messageAuthor({
      'id': '400000000000000001',
      'channel_id': '300000000000000001',
      'author': _user(bot: true, primaryGuild: _clan),
      'content': 'hi',
      'timestamp': '2026-07-25T10:00:00+00:00',
    })!;

    expect(author.isBot, isTrue);
    expect(author.clanTag?.tag, 'CODE');
    expect(author.clanTag?.guildId, _clanGuild);
    expect(
      author.clanTag?.badgeUrl,
      'https://cdn.discordapp.com/clan-badges/$_clanGuild/badgehash.webp'
      '?size=32',
    );
  });

  test('a guild member keeps the bot flag and the clan tag', () {
    final member = mapper.guildMember({
      'user': _user(bot: true, primaryGuild: _clan),
      'roles': <Object?>[],
    }, _guild);

    expect(member.isBot, isTrue);
    expect(member.clanTag?.tag, 'CODE');
  });

  test('a person with no clan is not a bot and has no tag', () {
    final member = mapper.member(_user());

    expect(member.isBot, isFalse);
    expect(member.clanTag, isNull);
  });

  test('a clan tag the user turned off is dropped', () {
    final member = mapper.member(
      _user(primaryGuild: {..._clan, 'identity_enabled': false}),
    );

    expect(member.clanTag, isNull);
  });

  test('a clan without a badge keeps its tag and no picture', () {
    final member = mapper.member(
      _user(primaryGuild: {..._clan, 'badge': null}),
    );

    expect(member.clanTag?.tag, 'CODE');
    expect(member.clanTag?.badgeUrl, isNull);
  });
}
