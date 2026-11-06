import 'package:flucord/src/application/voice_moderation.dart';
import 'package:flucord/src/data/discord/discord_guild_management_repository.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/permission_overwrite.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';

const _guild = '111111111111111111';
const _me = '222222222222222222';
const _friend = '333333333333333333';
const _lounge = '444444444444444444';
const _quiet = '555555555555555555';
const _closed = '666666666666666666';
const _general = '777777777777777777';

const _memberPath = '/api/v9/guilds/$_guild/members/$_friend';

ConversationChannel _channel(
  String id, {
  ChannelKind kind = ChannelKind.voice,
  Map<String, DiscordPermissionOverwrite> overwrites = const {},
}) => ConversationChannel(
  id: id,
  spaceId: _guild,
  name: 'room $id',
  topic: '',
  kind: kind,
  permissionOverwrites: overwrites,
);

/// A guild whose `@everyone` holds [everyone], with three voice channels and
/// a text one. Nobody may connect to [_closed].
ChatWorkspace _workspace(BigInt everyone) => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: _guild,
      name: 'Forge',
      monogram: 'F',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: [
    _channel(_lounge),
    _channel(_quiet),
    _channel(
      _closed,
      overwrites: {
        _guild: DiscordPermissionOverwrite(
          id: _guild,
          allow: BigInt.zero,
          deny: DiscordPermissions.connect,
        ),
      },
    ),
    _channel(_general, kind: ChannelKind.text),
  ],
  roles: [
    CommunityRole(
      id: _guild,
      spaceId: _guild,
      name: '@everyone',
      position: 0,
      permissions: everyone,
    ),
  ],
  members: const [
    Member(
      id: _me,
      displayName: 'Ada',
      initials: 'A',
      role: 'Member',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: {_guild},
      membershipsBySpace: {_guild: GuildMembership()},
    ),
  ],
  messages: const [],
  currentMemberId: _me,
);

final _base = DiscordPermissions.combine([
  DiscordPermissions.viewChannel,
  DiscordPermissions.connect,
]);

final _moderator = DiscordPermissions.combine([
  _base,
  DiscordPermissions.muteMembers,
  DiscordPermissions.deafenMembers,
  DiscordPermissions.moveMembers,
]);

VoiceParticipantStateEvent _seat({
  String? guildId = _guild,
  bool serverMuted = false,
  bool serverDeafened = false,
}) => VoiceParticipantStateEvent(
  userId: _friend,
  guildId: guildId,
  channelId: _lounge,
  selfMuted: false,
  selfDeafened: false,
  serverMuted: serverMuted,
  serverDeafened: serverDeafened,
  isStreaming: false,
  isVideoEnabled: false,
);

/// The moderation of the friend seated in [_lounge], over the desktop routes.
({FakeDiscordTransport transport, ParticipantModeration? moderation}) _setUp(
  BigInt everyone, {
  VoiceParticipantStateEvent? seat,
}) {
  final transport = FakeDiscordTransport()
    ..on('PATCH', _memberPath, (_) => jsonResponse({'roles': <String>[]}));
  final moderation = VoiceModeration(
    members: DiscordGuildManagementRepository(
      DiscordRestClient(
        authorization: DiscordDesktopAuthorization('token'),
        transport: transport,
        baseUri: Uri.parse('https://discord.com/api/v9'),
      ),
    ),
    permissions: WorkspacePermissions(_workspace(everyone)),
  );
  return (transport: transport, moderation: moderation.of(seat ?? _seat()));
}

void main() {
  group('member route', () {
    test('Server Mute and its undo patch mute', () async {
      final (:transport, :moderation) = _setUp(_moderator);

      await moderation!.setServerMuted(true);
      await moderation.setServerMuted(false);

      expect(
        [for (final r in transport.requests) r.method],
        ['PATCH', 'PATCH'],
      );
      expect(transport.requests.first.uri.path, _memberPath);
      expect(
        [for (final r in transport.requests) r.json],
        [
          {'mute': true},
          {'mute': false},
        ],
      );
    });

    test('Server Deafen patches deaf', () async {
      final (:transport, :moderation) = _setUp(_moderator);

      await moderation!.setServerDeafened(true);

      expect(transport.requests.single.uri.path, _memberPath);
      expect(transport.requests.single.json, {'deaf': true});
    });

    test('Move To patches the channel', () async {
      final (:transport, :moderation) = _setUp(_moderator);

      await moderation!.moveTo(_quiet);

      expect(transport.requests.single.uri.path, _memberPath);
      expect(transport.requests.single.json, {'channel_id': _quiet});
    });

    test('Disconnect patches a null channel', () async {
      final (:transport, :moderation) = _setUp(_moderator);

      await moderation!.disconnect();

      expect(transport.requests.single.method, 'PATCH');
      expect(transport.requests.single.json, {'channel_id': null});
    });

    test('a refusal reaches the caller', () async {
      final (:transport, :moderation) = _setUp(_moderator);
      transport.on(
        'PATCH',
        _memberPath,
        (_) =>
            jsonResponse({'message': 'Missing Permissions'}, statusCode: 403),
      );

      expect(
        moderation!.setServerMuted(true),
        throwsA(isA<DiscordApiException>()),
      );
    });
  });

  group('permission gate', () {
    test('a moderator may do everything', () {
      final moderation = _setUp(_moderator).moderation!;

      expect(moderation.canMute, isTrue);
      expect(moderation.canDeafen, isTrue);
      expect(moderation.canDisconnect, isTrue);
      // Not the room they are in, not a text channel, not one the account
      // cannot connect to.
      expect([for (final c in moderation.moveTargets) c.id], [_quiet]);
    });

    test('each action follows its own permission', () {
      final mute = _setUp(_base | DiscordPermissions.muteMembers).moderation!;
      final deafen = _setUp(
        _base | DiscordPermissions.deafenMembers,
      ).moderation!;

      expect(
        (mute.canMute, mute.canDeafen, mute.canDisconnect),
        (true, false, false),
      );
      expect(mute.moveTargets, isEmpty);
      expect((deafen.canMute, deafen.canDeafen), (false, true));
    });

    test('an ordinary member gets nothing to offer', () {
      expect(_setUp(_base).moderation!.isEmpty, isTrue);
    });

    test('the voice state gives the server mute and deafen', () {
      final moderation = _setUp(
        _moderator,
        seat: _seat(serverMuted: true, serverDeafened: true),
      ).moderation!;

      expect(moderation.isServerMuted, isTrue);
      expect(moderation.isServerDeafened, isTrue);
    });

    test('a call outside a guild has no moderation', () {
      expect(_setUp(_moderator, seat: _seat(guildId: null)).moderation, isNull);
    });
  });
}
