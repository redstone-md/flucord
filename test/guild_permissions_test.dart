import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/guild_permissions.dart';
import 'package:flucord/src/domain/permission_overwrite.dart';
import 'package:flutter_test/flutter_test.dart';

part 'guild_permissions_clamp_cases.dart';
part 'guild_permissions_thread_cases.dart';

const _guild = 'guild-1';
const _member = 'member-1';
final _now = DateTime.utc(2026, 7, 26, 12);

DiscordPermissionOverwrite _overwrite(
  String id, {
  BigInt? allow,
  BigInt? deny,
}) => DiscordPermissionOverwrite(
  id: id,
  allow: allow ?? BigInt.zero,
  deny: deny ?? BigInt.zero,
);

GuildPermissions _permissions({
  Map<String, BigInt>? roles,
  String? ownerId,
  bool requiresMultiFactorAuth = false,
}) => GuildPermissions(
  guildId: _guild,
  rolePermissions:
      roles ??
      {
        _guild: DiscordPermissions.combine([
          DiscordPermissions.viewChannel,
          DiscordPermissions.sendMessages,
        ]),
      },
  ownerId: ownerId,
  requiresMultiFactorAuth: requiresMultiFactorAuth,
);

PermissionSubject _subject({
  GuildMembership? membership = const GuildMembership(),
  bool isCurrentUser = false,
  bool hasMultiFactorAuth = true,
  bool isLurking = false,
}) => PermissionSubject(
  userId: _member,
  membership: membership,
  isCurrentUser: isCurrentUser,
  hasMultiFactorAuth: hasMultiFactorAuth,
  isLurking: isLurking,
);

void main() {
  group('guild base', () {
    test('starts from the @everyone role, which is keyed by the guild id', () {
      final result = _permissions().of(_subject(), now: _now);

      expect(
        result,
        DiscordPermissions.combine([
          DiscordPermissions.viewChannel,
          DiscordPermissions.sendMessages,
        ]),
      );
    });

    test('unions the roles the member holds', () {
      final result =
          _permissions(
            roles: {
              _guild: DiscordPermissions.viewChannel,
              'role-a': DiscordPermissions.sendMessages,
              'role-b': DiscordPermissions.pinMessages,
              'role-unheld': DiscordPermissions.banMembers,
            },
          ).of(
            _subject(
              membership: const GuildMembership(roleIds: ['role-a', 'role-b']),
            ),
            now: _now,
          );

      expect(
        result,
        DiscordPermissions.combine([
          DiscordPermissions.viewChannel,
          DiscordPermissions.sendMessages,
          DiscordPermissions.pinMessages,
        ]),
      );
    });

    test('skips a role id no record exists for', () {
      final result =
          _permissions(roles: {_guild: DiscordPermissions.viewChannel}).of(
            _subject(
              membership: const GuildMembership(roleIds: ['stale-role']),
            ),
            now: _now,
          );

      expect(result, DiscordPermissions.viewChannel);
    });

    test('falls back to the default @everyone set when the role is absent', () {
      final result = _permissions(roles: const {}).of(_subject(), now: _now);

      expect(result, DiscordPermissions.defaultEveryone);
    });

    test('reads the clock itself when the caller passes no moment', () {
      final result = _permissions().of(_subject());

      expect(
        DiscordPermissions.hasAll(result, DiscordPermissions.sendMessages),
        isTrue,
      );
    });

    test('a guild-wide timeout clamps even with no channel involved', () {
      final result = _permissions().of(
        _subject(
          membership: GuildMembership(
            timeoutUntil: _now.add(const Duration(minutes: 5)),
          ),
        ),
        now: _now,
      );

      expect(result, DiscordPermissions.viewChannel);
    });
  });

  group('administrator', () {
    test('replaces the base with everything and skips the overwrites', () {
      final result =
          _permissions(
            roles: {
              _guild: DiscordPermissions.viewChannel,
              'role-a': DiscordPermissions.administrator,
            },
          ).inChannel(
            _subject(membership: const GuildMembership(roleIds: ['role-a'])),
            overwrites: {
              _guild: _overwrite(_guild, deny: DiscordPermissions.viewChannel),
            },
            now: _now,
          );

      expect(result, DiscordPermissions.all);
    });

    test('is judged before overwrites, so an overwrite cannot skip them', () {
      final result =
          _permissions(
            roles: {_guild: DiscordPermissions.viewChannel},
          ).inChannel(
            _subject(),
            overwrites: {
              _guild: _overwrite(
                _guild,
                allow: DiscordPermissions.administrator,
                deny: DiscordPermissions.viewChannel,
              ),
            },
            now: _now,
          );

      // The deny still applied: only the role-derived base short-circuits.
      expect(result, DiscordPermissions.administrator);
    });
  });

  group('overwrite pass', () {
    test('applies the @everyone overwrite even for an unknown member', () {
      final result = _permissions().inChannel(
        PermissionSubject(userId: _member),
        overwrites: {
          _guild: _overwrite(
            _guild,
            allow: DiscordPermissions.pinMessages,
            deny: DiscordPermissions.sendMessages,
          ),
          'role-a': _overwrite('role-a', allow: DiscordPermissions.banMembers),
        },
        now: _now,
      );

      expect(
        result,
        DiscordPermissions.combine([
          DiscordPermissions.viewChannel,
          DiscordPermissions.pinMessages,
        ]),
      );
    });

    test('unions every role deny before any role allow', () {
      // One role's deny must not beat another role's allow, whichever order
      // the ids happen to arrive in.
      final overwrites = {
        'role-a': _overwrite('role-a', deny: DiscordPermissions.sendMessages),
        'role-b': _overwrite('role-b', allow: DiscordPermissions.sendMessages),
      };
      final held = _permissions(
        roles: {_guild: DiscordPermissions.viewChannel},
      );

      for (final order in [
        const ['role-a', 'role-b'],
        const ['role-b', 'role-a'],
      ]) {
        final result = held.inChannel(
          _subject(membership: GuildMembership(roleIds: order)),
          overwrites: overwrites,
          now: _now,
        );

        expect(
          DiscordPermissions.hasAll(result, DiscordPermissions.sendMessages),
          isTrue,
          reason: order.join(' then '),
        );
      }
    });

    test('the member overwrite is applied after every role overwrite', () {
      final result =
          _permissions(
            roles: {_guild: DiscordPermissions.viewChannel},
          ).inChannel(
            _subject(membership: const GuildMembership(roleIds: ['role-a'])),
            overwrites: {
              'role-a': _overwrite(
                'role-a',
                allow: DiscordPermissions.sendMessages,
              ),
              _member: _overwrite(
                _member,
                deny: DiscordPermissions.sendMessages,
                allow: DiscordPermissions.pinMessages,
              ),
            },
            now: _now,
          );

      expect(
        result,
        DiscordPermissions.combine([
          DiscordPermissions.viewChannel,
          DiscordPermissions.pinMessages,
        ]),
      );
    });

    test('skips overwrites keyed to roles the member does not hold', () {
      final result = _permissions().inChannel(
        _subject(membership: const GuildMembership(roleIds: ['role-a'])),
        overwrites: {
          'role-other': _overwrite(
            'role-other',
            deny: DiscordPermissions.sendMessages,
          ),
        },
        now: _now,
      );

      expect(
        DiscordPermissions.hasAll(result, DiscordPermissions.sendMessages),
        isTrue,
      );
    });
  });

  _clampCases();

  group('owner and two-factor', () {
    test('the owner holds everything, whatever an overwrite denies', () {
      final result = _permissions(ownerId: _member).inChannel(
        _subject(
          membership: const GuildMembership(flags: GuildMembership.guestFlag),
        ),
        overwrites: {
          _guild: _overwrite(_guild, deny: DiscordPermissions.viewChannel),
        },
        now: _now,
      );

      expect(result, DiscordPermissions.all);
    });

    test('an elevated guild still strips the owner without two-factor', () {
      final result = _permissions(
        ownerId: _member,
        requiresMultiFactorAuth: true,
      ).of(_subject(isCurrentUser: true, hasMultiFactorAuth: false), now: _now);

      expect(
        result,
        DiscordPermissions.remove(
          DiscordPermissions.all,
          DiscordPermissions.mfaGated,
        ),
      );
    });

    test('the strip only touches the signed-in account that lacks it', () {
      final elevated = _permissions(
        roles: {_guild: DiscordPermissions.manageMessages},
        requiresMultiFactorAuth: true,
      );

      expect(
        elevated.of(
          _subject(isCurrentUser: true, hasMultiFactorAuth: false),
          now: _now,
        ),
        BigInt.zero,
      );
      expect(
        elevated.of(
          _subject(isCurrentUser: true, hasMultiFactorAuth: true),
          now: _now,
        ),
        DiscordPermissions.manageMessages,
      );
      expect(
        elevated.of(
          _subject(isCurrentUser: false, hasMultiFactorAuth: false),
          now: _now,
        ),
        DiscordPermissions.manageMessages,
      );
    });

    test('a guild that does not require two-factor never strips', () {
      final result = _permissions(
        roles: {_guild: DiscordPermissions.manageMessages},
      ).of(_subject(isCurrentUser: true, hasMultiFactorAuth: false), now: _now);

      expect(result, DiscordPermissions.manageMessages);
    });
  });

  _threadCases();
}
