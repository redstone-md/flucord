import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/permission_overwrite.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every named bit and the index Discord's own constant table gives it.
final _bits = <String, ({BigInt value, int index})>{
  'CREATE_INSTANT_INVITE': (
    value: DiscordPermissions.createInstantInvite,
    index: 0,
  ),
  'KICK_MEMBERS': (value: DiscordPermissions.kickMembers, index: 1),
  'BAN_MEMBERS': (value: DiscordPermissions.banMembers, index: 2),
  'ADMINISTRATOR': (value: DiscordPermissions.administrator, index: 3),
  'MANAGE_CHANNELS': (value: DiscordPermissions.manageChannels, index: 4),
  'MANAGE_GUILD': (value: DiscordPermissions.manageGuild, index: 5),
  'ADD_REACTIONS': (value: DiscordPermissions.addReactions, index: 6),
  'VIEW_AUDIT_LOG': (value: DiscordPermissions.viewAuditLog, index: 7),
  'PRIORITY_SPEAKER': (value: DiscordPermissions.prioritySpeaker, index: 8),
  'STREAM': (value: DiscordPermissions.stream, index: 9),
  'VIEW_CHANNEL': (value: DiscordPermissions.viewChannel, index: 10),
  'SEND_MESSAGES': (value: DiscordPermissions.sendMessages, index: 11),
  'SEND_TTS_MESSAGES': (value: DiscordPermissions.sendTtsMessages, index: 12),
  'MANAGE_MESSAGES': (value: DiscordPermissions.manageMessages, index: 13),
  'EMBED_LINKS': (value: DiscordPermissions.embedLinks, index: 14),
  'ATTACH_FILES': (value: DiscordPermissions.attachFiles, index: 15),
  'READ_MESSAGE_HISTORY': (
    value: DiscordPermissions.readMessageHistory,
    index: 16,
  ),
  'MENTION_EVERYONE': (value: DiscordPermissions.mentionEveryone, index: 17),
  'USE_EXTERNAL_EMOJIS': (
    value: DiscordPermissions.useExternalEmojis,
    index: 18,
  ),
  'VIEW_GUILD_ANALYTICS': (
    value: DiscordPermissions.viewGuildAnalytics,
    index: 19,
  ),
  'CONNECT': (value: DiscordPermissions.connect, index: 20),
  'SPEAK': (value: DiscordPermissions.speak, index: 21),
  'MUTE_MEMBERS': (value: DiscordPermissions.muteMembers, index: 22),
  'DEAFEN_MEMBERS': (value: DiscordPermissions.deafenMembers, index: 23),
  'MOVE_MEMBERS': (value: DiscordPermissions.moveMembers, index: 24),
  'USE_VAD': (value: DiscordPermissions.useVoiceActivity, index: 25),
  'CHANGE_NICKNAME': (value: DiscordPermissions.changeNickname, index: 26),
  'MANAGE_NICKNAMES': (value: DiscordPermissions.manageNicknames, index: 27),
  'MANAGE_ROLES': (value: DiscordPermissions.manageRoles, index: 28),
  'MANAGE_WEBHOOKS': (value: DiscordPermissions.manageWebhooks, index: 29),
  'MANAGE_GUILD_EXPRESSIONS': (
    value: DiscordPermissions.manageGuildExpressions,
    index: 30,
  ),
  'USE_APPLICATION_COMMANDS': (
    value: DiscordPermissions.useApplicationCommands,
    index: 31,
  ),
  'REQUEST_TO_SPEAK': (value: DiscordPermissions.requestToSpeak, index: 32),
  'MANAGE_EVENTS': (value: DiscordPermissions.manageEvents, index: 33),
  'MANAGE_THREADS': (value: DiscordPermissions.manageThreads, index: 34),
  'CREATE_PUBLIC_THREADS': (
    value: DiscordPermissions.createPublicThreads,
    index: 35,
  ),
  'CREATE_PRIVATE_THREADS': (
    value: DiscordPermissions.createPrivateThreads,
    index: 36,
  ),
  'USE_EXTERNAL_STICKERS': (
    value: DiscordPermissions.useExternalStickers,
    index: 37,
  ),
  'SEND_MESSAGES_IN_THREADS': (
    value: DiscordPermissions.sendMessagesInThreads,
    index: 38,
  ),
  'USE_EMBEDDED_ACTIVITIES': (
    value: DiscordPermissions.useEmbeddedActivities,
    index: 39,
  ),
  'MODERATE_MEMBERS': (value: DiscordPermissions.moderateMembers, index: 40),
  'VIEW_CREATOR_MONETIZATION_ANALYTICS': (
    value: DiscordPermissions.viewCreatorMonetizationAnalytics,
    index: 41,
  ),
  'USE_SOUNDBOARD': (value: DiscordPermissions.useSoundboard, index: 42),
  'CREATE_GUILD_EXPRESSIONS': (
    value: DiscordPermissions.createGuildExpressions,
    index: 43,
  ),
  'CREATE_EVENTS': (value: DiscordPermissions.createEvents, index: 44),
  'USE_EXTERNAL_SOUNDS': (
    value: DiscordPermissions.useExternalSounds,
    index: 45,
  ),
  'SEND_VOICE_MESSAGES': (
    value: DiscordPermissions.sendVoiceMessages,
    index: 46,
  ),
  'SET_VOICE_CHANNEL_STATUS': (
    value: DiscordPermissions.setVoiceChannelStatus,
    index: 48,
  ),
  'SEND_POLLS': (value: DiscordPermissions.sendPolls, index: 49),
  'USE_EXTERNAL_APPS': (value: DiscordPermissions.useExternalApps, index: 50),
  'PIN_MESSAGES': (value: DiscordPermissions.pinMessages, index: 51),
  'BYPASS_SLOWMODE': (value: DiscordPermissions.bypassSlowmode, index: 52),
  'MANAGE_OFFICIAL_MESSAGES': (
    value: DiscordPermissions.manageOfficialMessages,
    index: 53,
  ),
};

void main() {
  group('permission bits', () {
    test('every named bit sits at the documented index', () {
      for (final entry in _bits.entries) {
        expect(
          entry.value.value,
          BigInt.one << entry.value.index,
          reason: entry.key,
        );
      }
      expect(_bits.length, 53);
    });

    test('the table skips the unnamed bit 47', () {
      final unnamed = BigInt.one << 47;

      expect(_bits.values.map((bit) => bit.value), isNot(contains(unnamed)));
      expect(DiscordPermissions.all & unnamed, BigInt.zero);
    });

    test('ALL is every named bit and nothing else', () {
      // Bits 0..53 with 47 punched out, derived rather than pasted so the
      // expectation does not simply repeat the implementation's fold.
      final expected = (BigInt.one << 54) - BigInt.one - (BigInt.one << 47);

      expect(DiscordPermissions.all, expected);
      expect(
        DiscordPermissions.all,
        DiscordPermissions.combine(_bits.values.map((bit) => bit.value)),
      );
    });

    test('derived masks match the values Discord ships', () {
      expect(DiscordPermissions.none, BigInt.zero);
      expect(
        DiscordPermissions.defaultEveryone,
        BigInt.parse('1720707884502593'),
      );
      expect(DiscordPermissions.lurker, BigInt.from(66560));
      expect(DiscordPermissions.timeout, BigInt.from(66560));
      expect(DiscordPermissions.quarantine, BigInt.from(67175424));
      expect(DiscordPermissions.guest, BigInt.parse('1166444435131968'));
      expect(DiscordPermissions.mfaGated, BigInt.parse('1116959940670'));
    });
  });

  group('bitfield helpers', () {
    test('parses every wire shape and refuses the rest', () {
      expect(DiscordPermissions.parse('2048'), DiscordPermissions.sendMessages);
      expect(DiscordPermissions.parse(2048), DiscordPermissions.sendMessages);
      expect(
        DiscordPermissions.parse(DiscordPermissions.sendMessages),
        DiscordPermissions.sendMessages,
      );
      expect(DiscordPermissions.parse(null), BigInt.zero);
      expect(DiscordPermissions.parse('not-a-number'), BigInt.zero);
      expect(DiscordPermissions.parse(const []), BigInt.zero);
    });

    test('tryParse keeps absence distinguishable from zero', () {
      expect(DiscordPermissions.tryParse('0'), BigInt.zero);
      expect(DiscordPermissions.tryParse(null), isNull);
      expect(DiscordPermissions.tryParse('nonsense'), isNull);
      expect(DiscordPermissions.tryParse(true), isNull);
    });

    test('encodes the newest bits without losing precision', () {
      // 2^53 is past the range a double represents exactly; a client that
      // routed this through an int would send a neighbouring number.
      final encoded = DiscordPermissions.encode(
        DiscordPermissions.manageOfficialMessages,
      );

      expect(BigInt.parse(encoded), BigInt.one << 53);
      expect(DiscordPermissions.encode(BigInt.zero), '0');
    });

    test('hasAll and hasAny differ on a multi-bit mask', () {
      final mask = DiscordPermissions.combine([
        DiscordPermissions.sendMessages,
        DiscordPermissions.attachFiles,
      ]);

      expect(DiscordPermissions.hasAll(mask, mask), isTrue);
      expect(
        DiscordPermissions.hasAll(DiscordPermissions.sendMessages, mask),
        isFalse,
      );
      expect(
        DiscordPermissions.hasAny(DiscordPermissions.sendMessages, mask),
        isTrue,
      );
      expect(DiscordPermissions.hasAny(BigInt.zero, mask), isFalse);
    });

    test('add and remove leave unrelated bits alone', () {
      final base = DiscordPermissions.combine([
        DiscordPermissions.viewChannel,
        DiscordPermissions.sendMessages,
      ]);

      expect(
        DiscordPermissions.add(base, DiscordPermissions.pinMessages),
        base | DiscordPermissions.pinMessages,
      );
      expect(
        DiscordPermissions.remove(base, DiscordPermissions.sendMessages),
        DiscordPermissions.viewChannel,
      );
      // Removing a bit that was never present is not an error and never
      // produces a negative intermediate.
      expect(
        DiscordPermissions.remove(base, DiscordPermissions.banMembers),
        base,
      );
      expect(DiscordPermissions.combine(const []), BigInt.zero);
    });
  });

  group('permission overwrite', () {
    test('reads the wire shape including the member marker', () {
      final overwrite = DiscordPermissionOverwrite.fromJson(const {
        'id': 'role-1',
        'type': 1,
        'allow': '2048',
        'deny': '1024',
      })!;

      expect(overwrite.id, 'role-1');
      expect(overwrite.kind, PermissionOverwriteKind.member);
      expect(overwrite.kind.discordValue, 1);
      expect(overwrite.allow, DiscordPermissions.sendMessages);
      expect(overwrite.deny, DiscordPermissions.viewChannel);
      expect(overwrite.grants(DiscordPermissions.sendMessages), isTrue);
      expect(overwrite.grants(DiscordPermissions.viewChannel), isFalse);
      expect(overwrite.denies(DiscordPermissions.viewChannel), isTrue);
      expect(overwrite.toString(), contains('member'));
    });

    test('treats an unknown or absent type as a role overwrite', () {
      expect(
        DiscordPermissionOverwrite.fromJson(const {'id': 'a'})!.kind,
        PermissionOverwriteKind.role,
      );
      expect(
        DiscordPermissionOverwrite.fromJson(const {'id': 'a', 'type': 7})!.kind,
        PermissionOverwriteKind.role,
      );
      expect(
        PermissionOverwriteKind.fromDiscordValue(null),
        PermissionOverwriteKind.role,
      );
    });

    test('drops entries no lookup could ever match', () {
      expect(DiscordPermissionOverwrite.fromJson(const {}), isNull);
      expect(DiscordPermissionOverwrite.fromJson(const {'id': ''}), isNull);
      expect(DiscordPermissionOverwrite.fromJson(const {'id': 7}), isNull);
    });

    test('maps an array by id, skipping malformed entries', () {
      final overwrites = DiscordPermissionOverwrite.mapFromJson(const [
        {'id': 'role-1', 'allow': '1024'},
        {'id': ''},
        'not-an-object',
        {'id': 'role-1', 'allow': '2048'},
      ]);

      expect(overwrites.keys, ['role-1']);
      expect(overwrites['role-1']!.allow, DiscordPermissions.sendMessages);
      expect(DiscordPermissionOverwrite.mapFromJson(null), isEmpty);
      expect(
        () => overwrites['role-1'] = overwrites['role-1']!,
        throwsUnsupportedError,
      );
    });

    test('has value semantics', () {
      final left = DiscordPermissionOverwrite(
        id: 'role-1',
        allow: DiscordPermissions.sendMessages,
        deny: BigInt.zero,
      );
      final right = DiscordPermissionOverwrite(
        id: 'role-1',
        allow: DiscordPermissions.sendMessages,
        deny: BigInt.zero,
      );

      expect(left, right);
      expect(left.hashCode, right.hashCode);
      expect(
        left,
        isNot(
          DiscordPermissionOverwrite(
            id: 'role-1',
            allow: DiscordPermissions.sendMessages,
            deny: DiscordPermissions.viewChannel,
          ),
        ),
      );
      expect(left, isNot('role-1'));
    });
  });

  group('guild membership', () {
    test('reads the member flags permissions clamp on', () {
      const guest = GuildMembership(flags: GuildMembership.guestFlag);

      expect(guest.isGuest, isTrue);
      expect(guest.isQuarantined, isFalse);
      for (final flag in [128, 256, 1024]) {
        expect(GuildMembership(flags: flag).isQuarantined, isTrue);
        expect(GuildMembership(flags: flag).isGuest, isFalse);
      }
      const none = GuildMembership();
      expect(none.isGuest, isFalse);
      expect(none.isQuarantined, isFalse);
    });

    test('a timeout is judged against the caller of the clock', () {
      final now = DateTime.utc(2026, 7, 26, 12);

      expect(
        GuildMembership(
          timeoutUntil: now.add(const Duration(minutes: 1)),
        ).isTimedOutAt(now),
        isTrue,
      );
      expect(
        GuildMembership(
          timeoutUntil: now.subtract(const Duration(minutes: 1)),
        ).isTimedOutAt(now),
        isFalse,
      );
      expect(const GuildMembership().isTimedOutAt(now), isFalse);
    });

    test('has value semantics over its role list', () {
      const left = GuildMembership(roleIds: ['a', 'b']);

      expect(left, const GuildMembership(roleIds: ['a', 'b']));
      expect(
        left.hashCode,
        const GuildMembership(roleIds: ['a', 'b']).hashCode,
      );
      expect(left, isNot(const GuildMembership(roleIds: ['b', 'a'])));
      expect(left, isNot(const GuildMembership(roleIds: ['a'])));
      expect(left, isNot(const GuildMembership(roleIds: ['a', 'b'], flags: 1)));
      expect(left, isNot('a,b'));
    });
  });
}
