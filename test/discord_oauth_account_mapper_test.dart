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
        'discriminator': '0042',
        'avatar': 'avatar-hash',
        'banner': 'banner-hash',
        'accent_color': 0x5865F2,
        'locale': 'en-US',
        'verified': true,
        'mfa_enabled': true,
        'public_flags': 64,
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
      connections: const [
        {
          'id': 'spotify-1',
          'name': 'jack.fm',
          'type': 'spotify',
          'verified': true,
          'friend_sync': true,
          'show_activity': true,
          'two_way_link': true,
          'visibility': 1,
        },
        {'id': '', 'name': 'Malformed', 'type': 'steam'},
      ],
    );

    expect(account.displayName, 'Jack');
    expect(account.usernameLabel, 'jack#0042');
    expect(account.bannerUrl, contains('/banners/123456789012345678/'));
    expect(account.accentColor, 0x5865F2);
    expect(account.locale, 'en-US');
    expect(account.isVerified, isTrue);
    expect(account.mfaEnabled, isTrue);
    expect(account.publicFlags, 64);
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
    final connection = account.connections.single;
    expect(connection.name, 'jack.fm');
    expect(connection.type, 'spotify');
    expect(connection.verified, isTrue);
    expect(connection.friendSync, isTrue);
    expect(connection.showActivity, isTrue);
    expect(connection.twoWayLink, isTrue);
    expect(connection.isPublic, isTrue);
    expect(
      () => account.guilds.add(DiscordOAuthGuild(id: 'guild-2', name: 'Other')),
      throwsUnsupportedError,
    );
    expect(() => guild.features.add('MUTATED'), throwsUnsupportedError);
    expect(
      () => account.connections.add(
        DiscordOAuthConnection(id: 'x', name: 'x', type: 'github'),
      ),
      throwsUnsupportedError,
    );
  });

  test('rejects an invalid account identity', () {
    expect(
      () =>
          mapper.map(user: const {'id': 'user-without-name'}, guilds: const []),
      throwsA(isA<DiscordOAuthException>()),
    );
  });
}
