import 'dart:async';

import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/presentation/widgets/chat_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// A name is resolved for the server it shows in: the nickname that server
// gave, or else the person's own name.

const _friendId = SessionHarness.friendId;
const _guildId = SessionHarness.guildId;
const _channelId = SessionHarness.channelId;

/// Somebody nobody has told the app about.
const _strangerId = '100000000000000003';
const _farGuildId = '200000000000000002';
const _farChannelId = '300000000000000004';

const _messageId = '900000000000000500';
const _olderMessageId = '900000000000000100';

const _friend = {
  'id': _friendId,
  'username': 'friend',
  'global_name': 'Friend',
};
const _stranger = {
  'id': _strangerId,
  'username': 'stranger',
  'global_name': 'Stranger',
};

Map<String, Object?> _twoServers() {
  final ready = SessionHarness.defaultReady();
  ready['guilds'] = [
    ...ready['guilds']! as List<Object?>,
    rawGuild(
      id: _farGuildId,
      name: 'Far Away',
      channels: [rawChannel(id: _farChannelId, name: 'far')],
    ),
  ];
  return ready;
}

/// A message by [author] that mentions the stranger, as a page of history
/// carries it: no guild and no member.
Map<String, Object?> _historyMessage({
  String id = _messageId,
  String channelId = _channelId,
  Map<String, Object?> author = _friend,
  String timestamp = '2026-07-25T10:00:00+00:00',
}) => {
  ...rawMessage(
    id: id,
    channelId: channelId,
    authorId: author['id']! as String,
    content: 'ask <@$_strangerId>',
    timestamp: timestamp,
  ),
  'author': author,
  'mentions': [_stranger],
};

void _routeHistory(
  FakeDiscordTransport transport, {
  String channelId = _channelId,
  List<Map<String, Object?>>? messages,
}) => transport.on(
  'GET',
  '/api/v9/channels/$channelId/messages',
  (_) => jsonResponse(messages ?? [_historyMessage(channelId: channelId)]),
);

/// Discord's answer to a member request, naming each id with [nicks].
Future<void> _chunk(
  SessionHarness session,
  Map<String, String> nicks, {
  String guildId = _guildId,
}) => session.dispatch('GUILD_MEMBERS_CHUNK', {
  'guild_id': guildId,
  'members': [
    for (final MapEntry(key: id, value: nick) in nicks.entries)
      {
        'user': id == _friendId ? _friend : _stranger,
        'nick': nick,
        'roles': <Object?>[],
      },
  ],
});

ChatController _chat(WidgetTester tester) =>
    tester.widget<ChatScope>(find.byType(ChatScope)).notifier!;

Finder _inRow(String text, [String id = _messageId]) => find.descendant(
  of: find.byKey(ValueKey('message-$id')),
  matching: find.text(text),
);

void main() {
  testSession(
    'the author and the people mentioned show the nickname of this server',
    (tester, session) async {
      await session.openChannel(_channelId);
      await _chunk(session, {_friendId: 'Forge Friend'});
      await _chunk(session, {_strangerId: 'Forge Stranger'});

      expect(_inRow('Forge Friend'), findsOneWidget);
      expect(_inRow('@Forge Stranger'), findsOneWidget);
    },
    routes: _routeHistory,
  );

  testSession(
    'a nickname from one server shows in no other server and in no DM',
    (tester, session) async {
      await _chunk(session, {
        _friendId: 'Far Friend',
        _strangerId: 'Far Stranger',
      }, guildId: _farGuildId);

      await session.openChannel(_channelId);
      expect(_inRow('Friend'), findsOneWidget);
      expect(_inRow('@Stranger'), findsOneWidget);

      await session.openChannel(
        SessionHarness.dmChannelId,
        space: 'direct-messages',
      );
      expect(_inRow('Friend', '900000000000000002'), findsOneWidget);
      expect(_inRow('@Stranger', '900000000000000002'), findsOneWidget);
      expect(find.textContaining('Far Friend'), findsNothing);
      expect(find.textContaining('Far Stranger'), findsNothing);
    },
    ready: _twoServers(),
    routes: (transport) {
      _routeHistory(transport);
      _routeHistory(
        transport,
        channelId: SessionHarness.dmChannelId,
        messages: [
          _historyMessage(
            id: '900000000000000002',
            channelId: SessionHarness.dmChannelId,
          ),
        ],
      );
    },
  );

  testSession('the member on a message sets the nickname for its server', (
    tester,
    session,
  ) async {
    await session.openChannel(_channelId);
    await session.dispatch('MESSAGE_CREATE', {
      ..._historyMessage(id: '900000000000000005'),
      'guild_id': _guildId,
      'member': {'nick': 'Forge Friend', 'roles': <Object?>[]},
      'mentions': [
        {
          ..._stranger,
          'member': {'nick': 'Forge Stranger', 'roles': <Object?>[]},
        },
      ],
    });

    expect(_inRow('Forge Friend', '900000000000000005'), findsOneWidget);
    expect(_inRow('@Forge Stranger', '900000000000000005'), findsOneWidget);
  });

  testSession('a reply names the author by their nickname in this server', (
    tester,
    session,
  ) async {
    await session.openChannel(_channelId);
    await session.dispatch('MESSAGE_CREATE', {
      ..._historyMessage(id: '900000000000000006'),
      'guild_id': _guildId,
      'member': {'nick': 'Forge Friend', 'roles': <Object?>[]},
    });
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(session.messageRow('900000000000000006')),
    );
    await session.settle();

    await tester.tap(find.byTooltip('Reply'));
    await session.settle();

    expect(find.text('Replying to Forge Friend'), findsOneWidget);
  });

  testSession(
    'a page of history does not turn a nickname back into the own name',
    (tester, session) async {
      await session.openChannel(_channelId);
      await _chunk(session, {
        _friendId: 'Forge Friend',
        _strangerId: 'Forge Stranger',
      });

      // Leaving and coming back loads the newest page again, and scrolling
      // back loads an older one.
      await session.openChannel(SessionHarness.otherChannelId);
      await session.openChannel(_channelId);
      unawaited(_chat(tester).loadOlderMessages(_channelId));
      await session.settle();

      expect(
        _chat(tester).workspace!.messagesFor(_channelId).first.id,
        _olderMessageId,
      );
      expect(_inRow('Forge Friend'), findsOneWidget);
      expect(_inRow('@Forge Stranger'), findsOneWidget);
    },
    routes: (transport) => transport.on(
      'GET',
      '/api/v9/channels/$_channelId/messages',
      (request) => jsonResponse(
        request.uri.queryParameters.containsKey('before')
            ? [
                _historyMessage(
                  id: _olderMessageId,
                  timestamp: '2026-07-25T08:00:00+00:00',
                ),
              ]
            // A full page, newest first, so there is more behind it.
            : [
                _historyMessage(),
                for (var index = 99; index > 0; index--)
                  _historyMessage(
                    id: '${900000000000000400 + index}',
                    timestamp: DateTime.utc(
                      2026,
                      7,
                      25,
                      9,
                    ).add(Duration(seconds: index)).toIso8601String(),
                  ),
              ],
      ),
    ),
  );

  testSession('a member update with no nickname ends the nickname', (
    tester,
    session,
  ) async {
    await session.openChannel(_channelId);
    await _chunk(session, {_friendId: 'Forge Friend'});

    // Unlike a page of history, a member payload is the whole standing.
    await session.dispatch('GUILD_MEMBER_UPDATE', {
      'guild_id': _guildId,
      'user': _friend,
      'nick': null,
      'roles': <Object?>[],
    });

    expect(_inRow('Friend'), findsOneWidget);
  }, routes: _routeHistory);

  testSession('somebody mentioned is asked about with the authors', (
    tester,
    session,
  ) async {
    await session.openChannel(_channelId);

    final asked = [
      for (final frame in session.socket.frames)
        if (frame['op'] == 8)
          ...((frame['d']! as Map)['user_ids']! as List).cast<String>(),
    ];
    expect(asked, containsAll([_friendId, _strangerId]));

    await _chunk(session, {_strangerId: 'Forge Stranger'});
    expect(_inRow('@Forge Stranger'), findsOneWidget);
  }, routes: _routeHistory);

  testSession(
    'a cached server opens on its nicknames, and keeps them after a restart',
    (tester, session) async {
      await session.openChannel(_channelId);
      await _chunk(session, {
        _friendId: 'Forge Friend',
        _strangerId: 'Forge Stranger',
      });

      // The next launch asks Discord for the page, and gets no answer yet.
      final page = Completer<DiscordHttpResponse>();
      session.transport.on(
        'GET',
        '/api/v9/channels/$_channelId/messages',
        (_) => page.future,
      );
      await session.relaunch(ready: SessionHarness.defaultReady());
      await tester.tap(find.byKey(const ValueKey('space-$_guildId')));
      await session.settle();
      await tester.tap(find.byKey(const ValueKey('channel-$_channelId')));

      // The first frame that draws the message draws the nicknames.
      for (var frame = 0; frame < 200; frame++) {
        if (session.messageRow(_messageId).evaluate().isNotEmpty) break;
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(_inRow('Forge Friend'), findsOneWidget);
      expect(_inRow('@Forge Stranger'), findsOneWidget);

      page.complete(jsonResponse([_historyMessage()]));
      await session.settle();
      expect(_inRow('Forge Friend'), findsOneWidget);
      expect(_inRow('@Forge Stranger'), findsOneWidget);
    },
    onDisk: true,
    routes: _routeHistory,
  );
}
