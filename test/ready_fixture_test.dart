import 'dart:convert';
import 'dart:io';

import 'package:flucord/src/data/discord/discord_desktop_bootstrap.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_protocol.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fixture has the structure of a real READY, with all data replaced.
/// See docs/LIVE_CAPTURE.md for how it was made.
Map<String, Object?> _readyFixture() =>
    (jsonDecode(
              File(
                'test/fixtures/gateway/ready_sanitized.json',
              ).readAsStringSync(),
            )
            as Map)
        .cast<String, Object?>();

void main() {
  test('a READY with the real shape builds the workspace the user sees', () {
    final ready = _readyFixture();
    final protocol = DiscordDesktopGatewayProtocol(
      token: 'unused',
      properties: const {},
      profile: DiscordDesktopProtocolProfile.installedStable20260725,
    );

    final actions = protocol.accept({
      'op': 0,
      't': 'READY',
      's': 1,
      'd': ready,
    });
    final dispatch = actions.single as DiscordDesktopGatewayDispatch;
    final bootstrap = DiscordDesktopBootstrap()..acceptReady(dispatch.data);
    final snapshot = bootstrap.snapshot()!;
    final workspace = DiscordMapper().workspace(
      currentUser: snapshot.currentUser,
      guilds: snapshot.guilds,
      channelsByGuild: snapshot.channelsByGuild,
      rolesByGuild: snapshot.rolesByGuild,
      membersByGuild: snapshot.membersByGuild,
      directChannels: snapshot.directChannels,
      includeDirectMessagesSpace: true,
      currentUserRole: 'Discord user',
    );

    final guilds = (ready['guilds']! as List).cast<Map<String, Object?>>();
    expect(protocol.currentUserId, (ready['user']! as Map)['id']);
    expect(
      workspace.spaces.map((space) => space.id),
      containsAll(guilds.map((guild) => guild['id'])),
    );
    for (final space in workspace.spaces.where(
      (space) => guilds.any((guild) => guild['id'] == space.id),
    )) {
      expect(space.name, 'name_placeholder');
      expect(
        workspace.channels.where((channel) => channel.spaceId == space.id),
        isNotEmpty,
      );
    }
    // A DM row with no name means a recipient did not resolve against `users`.
    final oneToOneIds = (ready['private_channels']! as List)
        .cast<Map<String, Object?>>()
        .where((channel) => channel['type'] == 1)
        .map((channel) => channel['id']);
    expect(oneToOneIds, isNotEmpty);
    for (final id in oneToOneIds) {
      final row = workspace.channels.singleWhere((channel) => channel.id == id);
      expect(row.name, isIn(['name_placeholder', 'user_placeholder']));
    }
    expect(
      workspace.members.map((member) => member.id),
      contains(workspace.currentMemberId),
    );
  });
}
