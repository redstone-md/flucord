import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_oauth_account_mapper.dart';
import 'package:flucord/src/domain/discord_oauth.dart';

void main() {
  const mapper = DiscordOAuthAccountMapper();

  test('maps the documented OAuth guild directory without mutable aliases', () {
    final account = mapper.map(
      user: const {
        'id': '123456789012345678',
        'username': 'jack',
        'global_name': 'Jack',
        'avatar': 'avatar-hash',
      },
      guilds: const [
        {
          'id': 'guild-1',
          'name': 'The Forge',
          'icon': 'a_icon-hash',
          'banner': 'banner-hash',
          'owner': true,
          'permissions': '8',
          'features': ['COMMUNITY', 'BANNER'],
          'approximate_member_count': 3268,
          'approximate_presence_count': 784,
        },
        {'id': '', 'name': 'Malformed'},
      ],
    );

    expect(account.displayName, 'Jack');
    expect(account.guildCount, 1);
    final guild = account.guilds.single;
    expect(guild.name, 'The Forge');
    expect(guild.iconUrl, contains('/icons/guild-1/a_icon-hash.gif'));
    expect(guild.bannerUrl, contains('/banners/guild-1/banner-hash.webp'));
    expect(guild.isOwner, isTrue);
    expect(guild.isAdministrator, isTrue);
    expect(guild.features, containsAll(const ['COMMUNITY', 'BANNER']));
    expect(guild.approximateMemberCount, 3268);
    expect(guild.approximatePresenceCount, 784);
    expect(
      () => account.guilds.add(DiscordOAuthGuild(id: 'guild-2', name: 'Other')),
      throwsUnsupportedError,
    );
    expect(() => guild.features.add('MUTATED'), throwsUnsupportedError);
  });

  test('rejects an invalid account identity', () {
    expect(
      () =>
          mapper.map(user: const {'id': 'user-without-name'}, guilds: const []),
      throwsA(isA<DiscordOAuthException>()),
    );
  });
}
