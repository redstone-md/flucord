import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/presentation/widgets/chat_scope.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _guildId = SessionHarness.guildId;
const _channelId = SessionHarness.channelId;
const _speakerId = '600000000000000001';
const _joinedGuildId = '200000000000000050';
const _lobbyId = '300000000000000051';
const _staffId = '300000000000000052';
const _emojiId = '700000000000000001';
const _stickerId = '700000000000000002';

final _readOnly = DiscordPermissions.combine([
  DiscordPermissions.viewChannel,
  DiscordPermissions.readMessageHistory,
]);

/// The Forge, where `@everyone` may only read and the account's Speaker role
/// grants [speakerPermissions].
Map<String, Object?> _forge({required BigInt speakerPermissions}) {
  final guild = rawGuild(
    id: _guildId,
    name: 'The Forge',
    channels: [rawChannel(id: _channelId, name: 'general')],
    everyonePermissions: '$_readOnly',
  );
  return guild
    ..['roles'] = [
      ...guild['roles']! as List,
      {
        'id': _speakerId,
        'name': 'Speaker',
        'position': 1,
        'color': 0,
        'permissions': '$speakerPermissions',
      },
    ];
}

/// A guild where `@everyone` may only read, and the staff channel is hidden
/// from `@everyone`.
Map<String, Object?> _joinedGuild() =>
    rawGuild(
        id: _joinedGuildId,
        name: 'Joined',
        channels: [
          rawChannel(id: _lobbyId, name: 'lobby'),
          {
            ...rawChannel(id: _staffId, name: 'staff'),
            'permission_overwrites': [
              {
                'id': _joinedGuildId,
                'type': 0,
                'allow': '0',
                'deny': '${DiscordPermissions.viewChannel}',
              },
            ],
          },
        ],
        everyonePermissions: '$_readOnly',
      )
      ..['emojis'] = [
        {'id': _emojiId, 'name': 'anvil'},
      ]
      ..['stickers'] = [
        {'id': _stickerId, 'name': 'hammer', 'format_type': 1, 'tags': 'hi'},
      ];

/// READY with [guilds], where the account holds Speaker in The Forge and no
/// role anywhere else.
Map<String, Object?> _ready(List<Map<String, Object?>> guilds) =>
    SessionHarness.defaultReady()
      // Discord's user table leaves out the account itself.
      ..['users'] = [
        {'id': SessionHarness.friendId, 'username': 'friend'},
      ]
      ..['guilds'] = guilds
      ..['merged_members'] = [
        for (final guild in guilds)
          [
            {
              'user_id': SessionHarness.currentUserId,
              'roles': guild['id'] == _guildId ? [_speakerId] : <String>[],
            },
          ],
      ];

final _canSend = DiscordPermissions.combine([
  DiscordPermissions.viewChannel,
  DiscordPermissions.sendMessages,
]);

Map<String, Object?> _readyBefore() =>
    _ready([_forge(speakerPermissions: _canSend)]);

/// [_readyBefore] after a stretch offline: Speaker lost the right to send, and
/// the account joined a guild.
Map<String, Object?> _readyAfter() => _ready([
  _forge(speakerPermissions: DiscordPermissions.viewChannel),
  _joinedGuild(),
]);

/// The session ends and the client identifies again, with this READY.
Future<void> _identifyAgain(
  SessionHarness session,
  Map<String, Object?> ready,
) async {
  session.socket.receive(const {'op': 9, 'd': false});
  await session.settle();
  await session.dispatch('READY', ready);
}

Finder get _readOnlyNotice =>
    find.byKey(const ValueKey('read-only-channel-notice'));

Finder _channelRow(String id) => find.byKey(ValueKey('channel-$id'));

void main() {
  group('what a reconnect changes in roles', () {
    // The lists are compared by identity: a fold that changes nothing keeps
    // them, so nothing downstream redraws or recomputes.
    testSession(
      'a reconnect that changes no role, emoji, sticker or membership keeps '
      'them as they were',
      (tester, session) async {
        final chat = tester.widget<ChatScope>(find.byType(ChatScope)).notifier!;
        await _identifyAgain(session, _readyAfter());
        final before = chat.workspace!;

        await _identifyAgain(session, _readyAfter());

        final after = chat.workspace!;
        expect(after.roles, same(before.roles));
        expect(after.emojis, same(before.emojis));
        expect(after.stickers, same(before.stickers));
        expect(
          after.memberOrNull(SessionHarness.currentUserId),
          same(before.memberOrNull(SessionHarness.currentUserId)),
        );
      },
      ready: _readyBefore(),
    );

    testSession(
      'a role that lost a permission offline locks the composer',
      (tester, session) async {
        await session.openChannel(_channelId);
        expect(_readOnlyNotice, findsNothing);

        await _identifyAgain(session, _readyAfter());

        expect(_readOnlyNotice, findsOneWidget);
      },
      ready: _readyBefore(),
    );

    testSession(
      'a guild joined offline hides what its roles hide and locks what they '
      'lock',
      (tester, session) async {
        await _identifyAgain(session, _readyAfter());

        await session.openChannel(_lobbyId, space: _joinedGuildId);

        expect(_channelRow(_lobbyId), findsOneWidget);
        expect(_channelRow(_staffId), findsNothing);
        expect(_readOnlyNotice, findsOneWidget);
      },
      ready: _readyBefore(),
    );

    testSession(
      "a guild joined offline brings its emoji and stickers to the pickers",
      (tester, session) async {
        await _identifyAgain(
          session,
          _ready([_forge(speakerPermissions: _canSend), _joinedGuild()]),
        );
        await session.openChannel(_channelId);

        await tester.tap(find.byKey(const ValueKey('open-emoji-picker')));
        await session.settle();
        expect(
          find.byKey(const ValueKey('emoji-choice-custom-$_emojiId')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await session.settle();

        await tester.tap(find.byKey(const ValueKey('open-sticker-picker')));
        await session.settle();
        expect(
          find.byKey(const ValueKey('sticker-option-$_stickerId')),
          findsOneWidget,
        );
      },
      ready: _readyBefore(),
    );

    testSession(
      'an offline launch finds the roles, the membership, the emoji and the '
      'stickers the reconnect wrote',
      (tester, session) async {
        await _identifyAgain(session, _readyAfter());

        await session.relaunchUnreachable();

        await session.openChannel(_channelId);
        expect(_readOnlyNotice, findsOneWidget);
        await session.openChannel(_lobbyId, space: _joinedGuildId);
        expect(_channelRow(_staffId), findsNothing);
        expect(_readOnlyNotice, findsOneWidget);
        final workspace = tester
            .widget<ChatScope>(find.byType(ChatScope))
            .notifier!
            .workspace!;
        expect(workspace.emojisFor(_joinedGuildId).map((emoji) => emoji.id), [
          _emojiId,
        ]);
        expect(
          workspace.stickersFor(_joinedGuildId).map((sticker) => sticker.id),
          [_stickerId],
        );
      },
      ready: _readyBefore(),
      onDisk: true,
    );
  });
}
