import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/voice_moderation.dart';
import 'package:flucord/src/data/discord/discord_guild_management_repository.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/fake_discord_wire.dart';
import 'support/stream_room_harness.dart';

const _friend = 'friend-1';
const _friendTile = ValueKey('voice-participant-$_friend');
const _memberPath = '/api/v9/guilds/guild-1/members/$_friend';

/// Where a moderator can move somebody from the room.
const _lounge = ConversationChannel(
  id: 'voice-2',
  spaceId: 'guild-1',
  name: 'Lounge',
  topic: '',
  kind: ChannelKind.voice,
);

const _rows = ['Server mute', 'Server deafen', 'Move to', 'Disconnect'];

/// The room's guild, where `@everyone` holds [everyone].
ChatWorkspace _guildWhere(BigInt everyone) => streamRoomWorkspace.copyWith(
  channels: [...streamRoomWorkspace.channels, _lounge],
  roles: [
    CommunityRole(
      id: 'guild-1',
      spaceId: 'guild-1',
      name: '@everyone',
      position: 0,
      permissions: everyone,
    ),
  ],
  members: [
    for (final member in streamRoomWorkspace.members)
      if (member.id == 'me')
        const Member(
          id: 'me',
          displayName: 'Me',
          initials: 'ME',
          role: 'Operator',
          presence: Presence.online,
          colorValue: 0xff4c9b72,
          spaceIds: {'guild-1'},
          membershipsBySpace: {'guild-1': GuildMembership()},
        )
      else
        member,
  ],
);

final _member = DiscordPermissions.combine([
  DiscordPermissions.viewChannel,
  DiscordPermissions.connect,
]);

final _moderator = DiscordPermissions.combine([
  _member,
  DiscordPermissions.muteMembers,
  DiscordPermissions.deafenMembers,
  DiscordPermissions.moveMembers,
]);

/// The voice channel's Room, where this account holds [everyone], over the
/// desktop member route.
Future<(StreamRoomHarness, FakeDiscordTransport)> _room(
  WidgetTester tester, {
  BigInt? everyone,
  List<StreamRoomSeat> seats = const [StreamRoomSeat(_friend)],
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final transport = FakeDiscordTransport()
    ..on('PATCH', _memberPath, (_) => jsonResponse({'roles': <String>[]}));
  final harness = await pumpStreamRoom(
    tester,
    streamRoomVoiceChannel,
    seats: seats,
    moderation: VoiceModeration(
      members: DiscordGuildManagementRepository(
        DiscordRestClient(
          authorization: DiscordDesktopAuthorization('token'),
          transport: transport,
          baseUri: Uri.parse('https://discord.com/api/v9'),
        ),
      ),
      permissions: WorkspacePermissions(_guildWhere(everyone ?? _moderator)),
    ),
  );
  return (harness, transport);
}

/// The colour of the mark [label] names.
Color? _markColour(WidgetTester tester, String label) => tester
    .widget<FlucordIcon>(
      find.descendant(
        of: find.byTooltip(label),
        matching: find.byType(FlucordIcon),
      ),
    )
    .color;

VoiceParticipantStateEvent _seatState({
  bool selfMuted = false,
  bool serverMuted = false,
  bool serverDeafened = false,
}) => VoiceParticipantStateEvent(
  userId: _friend,
  guildId: 'guild-1',
  channelId: 'voice-1',
  selfMuted: selfMuted,
  selfDeafened: false,
  serverMuted: serverMuted,
  serverDeafened: serverDeafened,
  isStreaming: false,
  isVideoEnabled: false,
);

Future<void> _openFriendMenu(WidgetTester tester) async {
  await tester.tapAt(
    tester.getCenter(find.byKey(_friendTile)),
    buttons: kSecondaryButton,
  );
  await tester.pumpAndSettle();
}

/// Chooses [row] and waits for the request it sends.
Future<void> _choose(WidgetTester tester, String row) async {
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

void main() {
  group('permission gate', () {
    testWidgets('a moderator gets every moderation row', (tester) async {
      await _room(tester);

      await _openFriendMenu(tester);

      for (final row in _rows) {
        expect(find.text(row), findsOneWidget);
      }
    });

    testWidgets('an ordinary member gets none', (tester) async {
      await _room(tester, everyone: _member);

      await _openFriendMenu(tester);

      expect(find.text('Mute'), findsOneWidget);
      for (final row in _rows) {
        expect(find.text(row), findsNothing);
      }
    });

    testWidgets('each row needs its own permission', (tester) async {
      await _room(tester, everyone: _member | DiscordPermissions.muteMembers);

      await _openFriendMenu(tester);

      expect(find.text('Server mute'), findsOneWidget);
      expect(find.text('Server deafen'), findsNothing);
      expect(find.text('Move to'), findsNothing);
      expect(find.text('Disconnect'), findsNothing);
    });
  });

  group('actions', () {
    testWidgets('Server mute sends the mute and the tile follows the state', (
      tester,
    ) async {
      final (harness, transport) = await _room(tester);
      await _openFriendMenu(tester);

      await _choose(tester, 'Server mute');

      expect(transport.requests.single.uri.path, _memberPath);
      expect(transport.requests.single.json, {'mute': true});
      // The tile changes when Discord says so, not before.
      expect(find.byTooltip('Server muted'), findsNothing);
      harness.reseat(const [StreamRoomSeat(_friend, isServerMuted: true)]);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Server muted'), findsOneWidget);
    });

    testWidgets('Server deafen shows ticked for a server-deafened friend', (
      tester,
    ) async {
      final (_, transport) = await _room(
        tester,
        seats: const [StreamRoomSeat(_friend, isServerDeafened: true)],
      );
      await _openFriendMenu(tester);

      await _choose(tester, 'Server deafen');

      expect(transport.requests.single.json, {'deaf': false});
    });

    testWidgets('Move to lists the other voice channels and moves there', (
      tester,
    ) async {
      final (_, transport) = await _room(tester);
      await _openFriendMenu(tester);

      await tester.tap(find.text('Move to'));
      await tester.pumpAndSettle();
      await _choose(tester, 'Lounge');

      expect(transport.requests.single.uri.path, _memberPath);
      expect(transport.requests.single.json, {'channel_id': 'voice-2'});
    });

    testWidgets('Disconnect sends a null channel', (tester) async {
      final (_, transport) = await _room(tester);
      await _openFriendMenu(tester);

      await _choose(tester, 'Disconnect');

      expect(transport.requests.single.json, {'channel_id': null});
    });

    testWidgets('a refusal is said in a snack bar', (tester) async {
      final (_, transport) = await _room(tester);
      transport.on(
        'PATCH',
        _memberPath,
        (_) =>
            jsonResponse({'message': 'Missing Permissions'}, statusCode: 403),
      );
      await _openFriendMenu(tester);

      await _choose(tester, 'Disconnect');

      expect(find.textContaining('Missing Permissions'), findsOneWidget);
    });
  });

  group('marks', () {
    testWidgets('a server mute is marked apart from a self-mute', (
      tester,
    ) async {
      await _room(
        tester,
        seats: const [
          StreamRoomSeat(_friend, isServerMuted: true),
          StreamRoomSeat('friend-2', isMuted: true),
        ],
      );

      expect(find.byTooltip('Server muted'), findsOneWidget);
      expect(find.byTooltip('Muted'), findsOneWidget);
      expect(
        _markColour(tester, 'Server muted'),
        isNot(_markColour(tester, 'Muted')),
      );
    });

    testWidgets('a seat in the sidebar marks a server mute apart', (
      tester,
    ) async {
      Widget seat(VoiceParticipantStateEvent state) => MaterialApp(
        theme: FlucordTheme.dark,
        home: Material(
          child: VoiceSeatRow(state: state, member: null, spaceId: 'guild-1'),
        ),
      );

      await tester.pumpWidget(seat(_seatState(selfMuted: true)));
      final selfMute = _markColour(tester, 'Muted');
      await tester.pumpWidget(seat(_seatState(serverMuted: true)));
      final serverMute = _markColour(tester, 'Server muted');
      await tester.pumpWidget(seat(_seatState(serverDeafened: true)));

      expect(serverMute, isNot(selfMute));
      expect(find.byTooltip('Server deafened'), findsOneWidget);
    });

    testWidgets('a server deafen is marked apart from a self-deafen', (
      tester,
    ) async {
      await _room(
        tester,
        seats: const [StreamRoomSeat(_friend, isServerDeafened: true)],
      );

      expect(find.byTooltip('Server deafened'), findsOneWidget);
      expect(find.byTooltip('Deafened'), findsNothing);
    });
  });
}
