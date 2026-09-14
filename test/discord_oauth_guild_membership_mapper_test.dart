import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_oauth_guild_membership_mapper.dart';
import 'package:flucord/src/domain/discord_oauth.dart';

void main() {
  const mapper = DiscordOAuthGuildMembershipMapper();

  test('maps documented membership fields without mutable role aliases', () {
    final membership = mapper.map(
      guildId: '987654321098765432',
      payload: const {
        'user': {'id': '123456789012345678'},
        'nick': 'Fly',
        'avatar': 'a_member-hash',
        'roles': ['role-1', 'role-2'],
        'joined_at': '2024-01-02T03:04:05+00:00',
        'premium_since': '2025-02-03T04:05:06Z',
        'pending': true,
        'communication_disabled_until': '2026-03-04T05:06:07Z',
      },
    );

    expect(membership.nickname, 'Fly');
    expect(membership.avatarUrl, endsWith('size=64'));
    expect(membership.roleIds, const ['role-1', 'role-2']);
    expect(membership.roleCount, 2);
    expect(membership.joinedAt, DateTime.utc(2024, 1, 2, 3, 4, 5));
    expect(membership.premiumSince, isNotNull);
    expect(membership.pending, isTrue);
    expect(membership.communicationDisabledUntil, isNotNull);
    expect(() => membership.roleIds.add('role-3'), throwsUnsupportedError);
  });

  test('rejects membership without its documented user identity', () {
    expect(
      () => mapper.map(
        guildId: '987654321098765432',
        payload: const {'roles': []},
      ),
      throwsA(isA<DiscordOAuthException>()),
    );
  });
}
