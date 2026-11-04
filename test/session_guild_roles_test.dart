import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _guildId = SessionHarness.guildId;
const _channelId = SessionHarness.channelId;
const _backstageId = '300000000000000040';
const _speakerId = '600000000000000001';
const _newRoleId = '600000000000000002';
const _crewId = '600000000000000003';
const _messageId = '900000000000000001';

const _red = 0xe74c3c;
const _blue = 0x3498db;
const _green = 0x2ecc71;

final _canSend = DiscordPermissions.combine([
  DiscordPermissions.viewChannel,
  DiscordPermissions.sendMessages,
]);

Map<String, Object?> _role(
  String id,
  String name, {
  required int color,
  required BigInt permissions,
  int position = 1,
  bool hoist = false,
}) => {
  'id': id,
  'name': name,
  'color': color,
  'position': position,
  'permissions': '$permissions',
  'hoist': hoist,
};

/// A guild where `@everyone` may only read, and the red Speaker role may send
/// and see the backstage channel. Speaker, and Crew above it, have their own
/// groups in the member list. The account holds [accountRoles].
Map<String, Object?> _ready({List<String> accountRoles = const [_speakerId]}) {
  final guild = rawGuild(
    id: _guildId,
    name: 'The Forge',
    channels: [
      rawChannel(id: _channelId, name: 'general'),
      {
        ...rawChannel(id: _backstageId, name: 'backstage'),
        'permission_overwrites': [
          {
            'id': _guildId,
            'type': 0,
            'allow': '0',
            'deny': '${DiscordPermissions.viewChannel}',
          },
          {
            'id': _speakerId,
            'type': 0,
            'allow': '${DiscordPermissions.viewChannel}',
            'deny': '0',
          },
        ],
      },
    ],
    everyonePermissions:
        '${DiscordPermissions.viewChannel | DiscordPermissions.readMessageHistory}',
  );
  guild['roles'] = [
    ...guild['roles']! as List,
    _role(
      _speakerId,
      'Speaker',
      color: _red,
      permissions: _canSend,
      hoist: true,
    ),
    _role(
      _crewId,
      'Crew',
      color: 0,
      permissions: DiscordPermissions.viewChannel,
      position: 2,
      hoist: true,
    ),
  ];
  return SessionHarness.defaultReady()
    ..['users'] = [
      {'id': SessionHarness.currentUserId, 'username': 'me'},
      {'id': SessionHarness.friendId, 'username': 'friend'},
    ]
    ..['merged_members'] = [
      [
        {'user_id': SessionHarness.currentUserId, 'roles': accountRoles},
      ],
    ]
    ..['guilds'] = [guild];
}

/// A message from the friend, who holds [roles] in the guild.
Future<void> _friendSays(SessionHarness session, List<String> roles) =>
    session.dispatch('MESSAGE_CREATE', {
      ...rawMessage(
        id: _messageId,
        channelId: _channelId,
        guildId: _guildId,
        authorId: SessionHarness.friendId,
        content: 'hello',
      ),
      'member': {'roles': roles},
    });

Color? _authorColor(WidgetTester tester, SessionHarness session) => tester
    .widget<Text>(
      find.descendant(
        of: find.descendant(
          of: session.messageRow(_messageId),
          matching: find.byKey(const ValueKey('message-author-name')),
        ),
        matching: find.byType(Text),
      ),
    )
    .style
    ?.color;

Finder get _readOnlyNotice =>
    find.byKey(const ValueKey('read-only-channel-notice'));

Finder get _backstageRow => find.byKey(const ValueKey('channel-$_backstageId'));

/// The member list's group labels, top to bottom, leaving out Offline.
List<String> _groupsTopToBottom(WidgetTester tester) {
  final labels = [
    for (final element
        in find
            .descendant(
              of: find.byType(MemberSidebar),
              matching: find.textContaining(' - '),
            )
            .evaluate())
      (element.widget as Text).data!,
  ]..removeWhere((label) => label.startsWith('Offline'));
  double top(String label) => tester.getTopLeft(find.text(label)).dy;
  return labels..sort((left, right) => top(left).compareTo(top(right)));
}

Future<void> _roleChanges(
  SessionHarness session,
  String event,
  Map<String, Object?> role,
) => session.dispatch(event, {'guild_id': _guildId, 'role': role});

void main() {
  group('a role that changes while the app runs', () {
    testSession('an updated role recolours its holders and changes what '
        'they may do', (tester, session) async {
      await session.openChannel(_channelId);
      await _friendSays(session, [_speakerId]);
      expect(_authorColor(tester, session), const Color(0xff000000 | _red));
      expect(_readOnlyNotice, findsNothing);

      await _roleChanges(
        session,
        'GUILD_ROLE_UPDATE',
        _role(
          _speakerId,
          'Speaker',
          color: _blue,
          permissions: DiscordPermissions.viewChannel,
        ),
      );

      expect(_authorColor(tester, session), const Color(0xff000000 | _blue));
      expect(_readOnlyNotice, findsOneWidget);
    }, ready: _ready());

    testSession(
      'a created role colours and permits a member once they hold it',
      (tester, session) async {
        await session.openChannel(_channelId);
        expect(_readOnlyNotice, findsOneWidget);

        await _roleChanges(
          session,
          'GUILD_ROLE_CREATE',
          _role(_newRoleId, 'Helper', color: _green, permissions: _canSend),
        );
        await session.dispatch('GUILD_MEMBER_UPDATE', {
          'guild_id': _guildId,
          'roles': [_newRoleId],
          'user': {'id': SessionHarness.currentUserId, 'username': 'me'},
        });
        await _friendSays(session, [_newRoleId]);

        expect(_authorColor(tester, session), const Color(0xff000000 | _green));
        expect(_readOnlyNotice, findsNothing);
      },
      ready: _ready(accountRoles: const []),
    );

    testSession(
      'a deleted role takes its colour, its permissions and its channels',
      (tester, session) async {
        await session.openChannel(_channelId);
        await _friendSays(session, [_speakerId]);
        expect(_backstageRow, findsOneWidget);

        await session.dispatch('GUILD_ROLE_DELETE', {
          'guild_id': _guildId,
          'role_id': _speakerId,
        });

        expect(
          _authorColor(tester, session),
          isNot(const Color(0xff000000 | _red)),
        );
        expect(_readOnlyNotice, findsOneWidget);
        expect(_backstageRow, findsNothing);
      },
      ready: _ready(),
    );

    testSession(
      'a renamed and moved role leads the member list under its new name',
      (tester, session) async {
        await session.dispatch('GUILD_MEMBER_UPDATE', {
          'guild_id': _guildId,
          'roles': [_crewId],
          'user': {'id': SessionHarness.friendId, 'username': 'friend'},
        });
        await session.dispatch('PRESENCE_UPDATE', {
          'guild_id': _guildId,
          'user': {'id': SessionHarness.friendId},
          'status': 'online',
        });
        await session.openChannel(_channelId);
        expect(_groupsTopToBottom(tester), ['Crew - 1', 'Speaker - 1']);

        await _roleChanges(
          session,
          'GUILD_ROLE_UPDATE',
          _role(
            _speakerId,
            'Stage',
            color: _red,
            permissions: _canSend,
            position: 3,
            hoist: true,
          ),
        );

        expect(_groupsTopToBottom(tester), ['Stage - 1', 'Crew - 1']);
      },
      ready: _ready(),
    );

    testSession(
      'an offline launch finds the role as it was changed',
      (tester, session) async {
        await _roleChanges(
          session,
          'GUILD_ROLE_UPDATE',
          _role(
            _speakerId,
            'Speaker',
            color: _blue,
            permissions: DiscordPermissions.viewChannel,
          ),
        );

        await session.relaunchUnreachable();
        await session.openChannel(_channelId);

        expect(_readOnlyNotice, findsOneWidget);
      },
      ready: _ready(),
      onDisk: true,
    );
  });
}
