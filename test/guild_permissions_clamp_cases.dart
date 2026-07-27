part of 'guild_permissions_test.dart';

void _clampCases() {
  group('clamps', () {
    test('a timed-out member keeps only what a reader needs', () {
      final result =
          _permissions(
            // Everything short of ADMINISTRATOR, which would exempt them.
            roles: {
              _guild: DiscordPermissions.remove(
                DiscordPermissions.all,
                DiscordPermissions.administrator,
              ),
            },
          ).inChannel(
            _subject(
              membership: GuildMembership(
                roleIds: const [],
                timeoutUntil: _now.add(const Duration(hours: 1)),
              ),
            ),
            now: _now,
          );

      expect(result, DiscordPermissions.timeout);
    });

    test('an expired timeout does not clamp', () {
      final result = _permissions().inChannel(
        _subject(
          membership: GuildMembership(
            timeoutUntil: _now.subtract(const Duration(seconds: 1)),
          ),
        ),
        now: _now,
      );

      expect(
        DiscordPermissions.hasAll(result, DiscordPermissions.sendMessages),
        isTrue,
      );
    });

    test('quarantine clamps, and an administrator is exempt', () {
      const quarantined = GuildMembership(flags: 128);
      final clamped = _permissions().inChannel(
        _subject(membership: quarantined),
        now: _now,
      );
      final exempt = _permissions().inChannel(
        _subject(membership: quarantined),
        overwrites: {
          _guild: _overwrite(_guild, allow: DiscordPermissions.administrator),
        },
        now: _now,
      );

      expect(clamped, DiscordPermissions.viewChannel);
      expect(
        DiscordPermissions.hasAll(exempt, DiscordPermissions.sendMessages),
        isTrue,
      );
    });

    test('a timed-out administrator is exempt too', () {
      final result = _permissions().inChannel(
        _subject(
          membership: GuildMembership(
            timeoutUntil: _now.add(const Duration(hours: 1)),
          ),
        ),
        overwrites: {
          _guild: _overwrite(_guild, allow: DiscordPermissions.administrator),
        },
        now: _now,
      );

      expect(
        DiscordPermissions.hasAll(result, DiscordPermissions.sendMessages),
        isTrue,
      );
    });

    test('lurking and pending both clamp to look-only', () {
      final lurking = _permissions(
        roles: {_guild: DiscordPermissions.all},
      ).of(_subject(isLurking: true), now: _now);
      final pending = _permissions(roles: {_guild: DiscordPermissions.all}).of(
        _subject(membership: const GuildMembership(isPending: true)),
        now: _now,
      );

      expect(lurking, DiscordPermissions.lurker);
      expect(pending, DiscordPermissions.lurker);
    });

    test('a guest keeps only the guest set', () {
      final result = _permissions(roles: {_guild: DiscordPermissions.all}).of(
        _subject(
          membership: const GuildMembership(flags: GuildMembership.guestFlag),
        ),
        now: _now,
      );

      expect(result, DiscordPermissions.guest);
    });

    test('the lurker clamp runs after overwrites, not before', () {
      // An overwrite that grants SEND_MESSAGES cannot lift the clamp.
      final result = _permissions().inChannel(
        _subject(isLurking: true),
        overwrites: {
          _guild: _overwrite(
            _guild,
            allow: DiscordPermissions.combine([
              DiscordPermissions.sendMessages,
              DiscordPermissions.readMessageHistory,
            ]),
          ),
        },
        now: _now,
      );

      expect(result, DiscordPermissions.lurker);
    });
  });
}
