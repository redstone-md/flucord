import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

final _server = find.byKey(const ValueKey('space-${SessionHarness.guildId}'));
final _invite = find.byKey(const ValueKey('invite-people'));
final _editProfile = find.byKey(const ValueKey('edit-server-profile'));

const _invitesPath = '/api/v9/channels/${SessionHarness.channelId}/invites';
const _ownMemberPath = '/api/v9/guilds/${SessionHarness.guildId}/members/@me';
const _readOwnMemberPath =
    '/api/v9/users/@me/guilds/${SessionHarness.guildId}/member';
const _me = {'id': SessionHarness.currentUserId, 'username': 'me'};
const _myMessageId = '900000000000000007';

/// The default READY, with [extra] granted to everybody in the guild, and
/// the account's own membership, so its permissions there are known.
Map<String, Object?> _readyGranting(BigInt extra) {
  final ready = SessionHarness.defaultReady()
    ..['merged_members'] = [
      [
        {'user_id': SessionHarness.currentUserId, 'roles': <String>[]},
      ],
    ];
  final guild = (ready['guilds']! as List).single as Map<String, Object?>;
  final everyone = (guild['roles']! as List).single as Map<String, Object?>;
  everyone['permissions'] =
      '${BigInt.parse(everyone['permissions']! as String) | extra}';
  return ready;
}

Future<void> _openServerMenu(
  WidgetTester tester,
  SessionHarness session,
) async {
  final mouse = await tester.startGesture(
    tester.getCenter(_server),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await mouse.up();
  await session.settle();
}

void main() {
  testSession(
    'a member who may invite gets a link from the server menu',
    (tester, session) async {
      await _openServerMenu(tester, session);
      await tester.tap(_invite);
      await session.settle();

      final ask = session.transport.requests.singleWhere(
        (request) => request.uri.path == _invitesPath,
      );
      expect(ask.method, 'POST');
      expect(ask.json, containsPair('max_age', 604800));
      expect(find.text('https://discord.gg/forge'), findsOneWidget);
    },
    ready: _readyGranting(DiscordPermissions.createInstantInvite),
    routes: (transport) => transport.on(
      'POST',
      _invitesPath,
      (_) => jsonResponse({'code': 'forge', 'max_age': 604800}),
    ),
    platform: TargetPlatform.windows,
  );

  testSession(
    'a member who may not invite or rename has neither row',
    (tester, session) async {
      await _openServerMenu(tester, session);

      expect(find.byKey(const ValueKey('leave-server')), findsOneWidget);
      expect(_invite, findsNothing);
      expect(_editProfile, findsNothing);
    },
    ready: _readyGranting(BigInt.zero),
    platform: TargetPlatform.windows,
  );

  testSession(
    'a nickname saved for the server shows on messages and in the member list',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _openServerMenu(tester, session);
      await tester.tap(_editProfile);
      await session.settle();

      await tester.enterText(
        find.byKey(const ValueKey('server-profile-nickname')),
        'Smith',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('server-profile-save')));
      await session.settle();

      final save = session.transport.requests.singleWhere(
        (request) => request.method == 'PATCH',
      );
      expect(save.uri.path, _ownMemberPath);
      expect(save.json, {'nick': 'Smith'});

      // Discord answers the change with the update every client gets.
      await session.dispatch('GUILD_MEMBER_UPDATE', {
        'guild_id': SessionHarness.guildId,
        'user': _me,
        'nick': 'Smith',
        'roles': <Object?>[],
      });

      expect(
        find.descendant(
          of: session.messageRow(_myMessageId),
          matching: find.text('Smith'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('member-row-${SessionHarness.currentUserId}'),
          ),
          matching: find.text('Smith'),
        ),
        findsOneWidget,
      );
    },
    ready: _readyGranting(DiscordPermissions.changeNickname),
    routes: (transport) {
      transport
        ..on(
          'GET',
          '/api/v9/channels/${SessionHarness.channelId}/messages',
          (_) => jsonResponse([
            {
              ...rawMessage(
                id: _myMessageId,
                channelId: SessionHarness.channelId,
                authorId: SessionHarness.currentUserId,
                content: 'hello',
              ),
              'author': _me,
            },
          ]),
        )
        ..on(
          'GET',
          _readOwnMemberPath,
          (_) => jsonResponse({'user': _me, 'roles': <Object?>[]}),
        )
        ..on(
          'PATCH',
          _ownMemberPath,
          (_) => jsonResponse({
            'user': _me,
            'nick': 'Smith',
            'roles': <Object?>[],
          }),
        );
    },
    platform: TargetPlatform.windows,
  );
}
