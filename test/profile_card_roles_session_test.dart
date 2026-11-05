import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// FLUCORD-98: a moderator takes a role away with the "x" on its chip.

const _guildId = SessionHarness.guildId;
const _messageId = '900000000000000041';
const _moderatorRoleId = '400000000000000001';
const _gamersRoleId = '400000000000000002';
const _friendPath =
    '/api/v9/guilds/$_guildId/members/${SessionHarness.friendId}';
const _removePath = '$_friendPath/roles/$_gamersRoleId';

final _gamersChip = find.byKey(
  const ValueKey('profile-card-role-$_gamersRoleId'),
);
final _removeGamers = find.byKey(
  const ValueKey('profile-card-role-remove-$_gamersRoleId'),
);

final _readAndWrite = DiscordPermissions.combine([
  DiscordPermissions.viewChannel,
  DiscordPermissions.sendMessages,
  DiscordPermissions.readMessageHistory,
]);

/// The Forge's roles. The account's Moderator role holds [moderator] and
/// sits at position 2; the friend's Gamers role sits at [gamersPosition].
List<Map<String, Object?>> _roles(BigInt moderator, int gamersPosition) => [
  {
    'id': _guildId,
    'name': '@everyone',
    'position': 0,
    'permissions': '$_readAndWrite',
  },
  {
    'id': _moderatorRoleId,
    'name': 'Moderator',
    'position': 2,
    'permissions': '$moderator',
  },
  {
    'id': _gamersRoleId,
    'name': 'Gamers',
    'position': gamersPosition,
    'permissions': '0',
  },
];

/// A session where the account holds Moderator and the friend holds Gamers,
/// with Discord answering the card's reads and the removal.
void _moderating(
  String description, {
  required BigInt moderator,
  int gamersPosition = 1,
  required Future<void> Function(WidgetTester, SessionHarness) body,
}) {
  final roles = _roles(moderator, gamersPosition);
  final ready = SessionHarness.defaultReady();
  (ready['guilds']! as List).first as Map<String, Object?>
    ..['roles'] = roles
    ..['members'] = [
      {
        'user': {'id': SessionHarness.currentUserId, 'username': 'me'},
        'roles': [_moderatorRoleId],
      },
      {
        'user': {'id': SessionHarness.friendId, 'username': 'friend'},
        'roles': [_gamersRoleId],
      },
    ];
  testSession(
    description,
    body,
    ready: ready,
    routes: (transport) => transport
      ..on('GET', '/api/v9/guilds/$_guildId/roles', (_) => jsonResponse(roles))
      ..on(
        'GET',
        _friendPath,
        (_) => jsonResponse({
          'user': {'id': SessionHarness.friendId, 'username': 'friend'},
          'roles': [_gamersRoleId],
        }),
      )
      ..on(
        'DELETE',
        _removePath,
        (_) =>
            const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ),
  );
}

Future<void> _openCard(WidgetTester tester, SessionHarness session) async {
  await session.openChannel(SessionHarness.channelId);
  await session.dispatch(
    'MESSAGE_CREATE',
    rawMessage(
      id: _messageId,
      channelId: SessionHarness.channelId,
      guildId: _guildId,
      authorId: SessionHarness.friendId,
      content: 'hello',
    ),
  );
  await tester.tap(
    find.descendant(
      of: session.messageRow(_messageId),
      matching: find.byKey(const ValueKey('message-author-name')),
    ),
  );
  await session.settle();
  expect(_gamersChip, findsOneWidget);
}

void main() {
  _moderating(
    'a moderator above the role takes it away with its "x"',
    moderator: DiscordPermissions.manageRoles,
    body: (tester, session) async {
      await _openCard(tester, session);

      await tester.tap(_removeGamers);
      await session.settle();

      expect(
        session.transport.requests.where(
          (request) =>
              request.method == 'DELETE' && request.uri.path == _removePath,
        ),
        hasLength(1),
      );
      expect(_gamersChip, findsNothing);
    },
  );

  _moderating(
    'without the right to manage roles no chip has an "x"',
    moderator: BigInt.zero,
    body: (tester, session) async {
      await _openCard(tester, session);

      expect(_removeGamers, findsNothing);
    },
  );

  _moderating(
    'a role above the account\'s own has no "x"',
    moderator: DiscordPermissions.manageRoles,
    gamersPosition: 3,
    body: (tester, session) async {
      await _openCard(tester, session);

      expect(_removeGamers, findsNothing);
    },
  );
}
