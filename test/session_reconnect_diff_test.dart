import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/presentation/widgets/chat_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _manyChannels = 5000;

const _guildId = SessionHarness.guildId;
const _dmChannelId = SessionHarness.dmChannelId;
const _leftGuildId = '200000000000000077';
const _leftChannelId = '300000000000000077';
const _categoryId = '300000000000000010';
const _goneCategoryId = '300000000000000020';
const _firstId = '300000000000000011';
const _secondId = '300000000000000012';
const _goneId = '300000000000000013';
const _thirdId = '300000000000000014';
const _gainedId = '300000000000000015';
const _gainedDmA = '400000000000000011';
const _gainedDmB = '400000000000000012';
const _friendA = '500000000000000011';
const _friendB = '500000000000000012';

ChatController _chat(WidgetTester tester) =>
    tester.widget<ChatScope>(find.byType(ChatScope)).notifier!;

Finder _channelRow(String id) => find.byKey(ValueKey('channel-$id'));

Finder _spaceRow(String id) => find.byKey(ValueKey('space-$id'));

Map<String, Object?> _guildOf(Map<String, Object?> ready) =>
    (ready['guilds']! as List).first as Map<String, Object?>;

/// READY for an account with one guild of [_manyChannels] channels, each named
/// with [label].
Map<String, Object?> _readyWithManyChannels(String label) {
  final ready = SessionHarness.defaultReady();
  _guildOf(ready)['channels'] = [
    for (var index = 0; index < _manyChannels; index++)
      rawChannel(id: '${310000000000000000 + index}', name: '$label-$index'),
  ];
  return ready;
}

Map<String, Object?> _channel(String id, String name, int position) => {
  ...rawChannel(id: id, name: name),
  'position': position,
};

Map<String, Object?> _category(String id, String name, int position) => {
  ..._channel(id, name, position),
  'type': 4,
};

/// Keeps its category on screen: the sidebar drops one with no channels.
final _inCategory = {
  ..._channel('300000000000000016', 'in-category', 7),
  'parent_id': _categoryId,
};

Map<String, Object?> _dm(String id, String friendId, {String? lastMessageId}) =>
    {
      'id': id,
      'type': 1,
      'recipient_ids': [friendId],
      'last_message_id': ?lastMessageId,
    };

Map<String, Object?> _user(String id) => {
  'id': id,
  'username': 'user-$id',
  'discriminator': '0',
  'avatar': null,
};

/// An account with a guild of four channels, another guild, and one DM.
Map<String, Object?> _readyBefore() {
  final ready = SessionHarness.defaultReady();
  _guildOf(ready)['channels'] = [
    _category(_categoryId, 'old-category', 0),
    _category(_goneCategoryId, 'gone-category', 6),
    _inCategory,
    _channel(_firstId, 'first', 1),
    _channel(_secondId, 'second', 2),
    _channel(_goneId, 'gone', 3),
    _channel(_thirdId, 'third', 4),
  ];
  ready['guilds'] = [
    _guildOf(ready),
    rawGuild(
      id: _leftGuildId,
      name: 'Left',
      channels: [_channel(_leftChannelId, 'left', 1)],
    ),
  ];
  return ready;
}

/// [_readyBefore], after a stretch offline: `second` and a category were renamed,
/// `gone` and the other category were deleted, a channel and two DMs were gained,
/// and the other guild was left.
Map<String, Object?> _readyAfter() {
  final ready = SessionHarness.defaultReady();
  _guildOf(ready)['channels'] = [
    _category(_categoryId, 'new-category', 0),
    _inCategory,
    _channel(_firstId, 'first', 1),
    _channel(_secondId, 'renamed', 2),
    _channel(_thirdId, 'third', 4),
    _channel(_gainedId, 'gained', 5),
  ];
  return _withGainedDms(ready);
}

/// [ready] with two more DMs, after the one it has.
Map<String, Object?> _withGainedDms(Map<String, Object?> ready) => ready
  ..['users'] = [...?ready['users'] as List?, _user(_friendA), _user(_friendB)]
  ..['private_channels'] = [
    ...ready['private_channels']! as List,
    _dm(_gainedDmA, _friendA),
    _dm(_gainedDmB, _friendB),
  ];

/// The session ends and the client identifies again, with this READY.
Future<void> _identifyAgain(
  SessionHarness session,
  Map<String, Object?> ready,
) async {
  session.socket.receive(const {'op': 9, 'd': false});
  await session.settle();
  await session.dispatch('READY', ready);
}

/// The ids of those [ids] that are on screen, from top to bottom.
List<String> _rowsTopToBottom(WidgetTester tester, List<String> ids) {
  final shown = [
    for (final id in ids)
      if (_channelRow(id).evaluate().isNotEmpty) id,
  ];
  return shown..sort(
    (left, right) => tester
        .getTopLeft(_channelRow(left))
        .dy
        .compareTo(tester.getTopLeft(_channelRow(right)).dy),
  );
}

const _guildChannels = [_firstId, _secondId, _goneId, _thirdId, _gainedId];
const _dms = [_dmChannelId, _gainedDmA, _gainedDmB];

Future<void> _showSpace(
  WidgetTester tester,
  SessionHarness session,
  String spaceId,
) async {
  await tester.tap(_spaceRow(spaceId));
  await session.settle();
}

void main() {
  testSession(
    'a re-identify that changes 5000 channels costs one notification and one '
    'commit more than a re-identify that changes none',
    (tester, session) async {
      final chat = _chat(tester);
      var notifications = 0;
      void count() => notifications++;
      chat.addListener(count);
      addTearDown(() => chat.removeListener(count));

      Future<(int, int)> costOf(Map<String, Object?> ready) async {
        session.socket.receive(const {'op': 9, 'd': false});
        await session.settle();
        final notificationsBefore = notifications;
        final commitsBefore = session.cacheCommits;
        await session.dispatch('READY', ready);
        return (
          notifications - notificationsBefore,
          session.cacheCommits - commitsBefore,
        );
      }

      final (quietNotifications, quietCommits) = await costOf(
        _readyWithManyChannels('before'),
      );
      final channelsBefore = chat.workspace!.channels;
      final (notified, commits) = await costOf(_readyWithManyChannels('after'));

      expect(notified, quietNotifications + 1);
      expect(commits, quietCommits + 1);
      expect(chat.workspace!.channels, isNot(same(channelsBefore)));
      final renamed = chat.workspace!.channelOrNull('310000000000004999')!;
      expect(renamed.name, 'after-4999');
    },
    ready: _readyWithManyChannels('before'),
  );

  group('what a reconnect changes', () {
    testSession(
      'removed, renamed and gained channels show in their places',
      (tester, session) async {
        await _identifyAgain(session, _readyAfter());
        await _showSpace(tester, session, _guildId);

        expect(_rowsTopToBottom(tester, _guildChannels), [
          _firstId,
          _secondId,
          _thirdId,
          _gainedId,
        ]);
        expect(
          find.descendant(
            of: _channelRow(_secondId),
            matching: find.text('renamed'),
          ),
          findsOneWidget,
        );
      },
      ready: _readyBefore(),
    );

    testSession(
      'a renamed category shows its new name, and a deleted one goes',
      (tester, session) async {
        await _identifyAgain(session, _readyAfter());
        await _showSpace(tester, session, _guildId);

        expect(
          find.textContaining(RegExp('new-category', caseSensitive: false)),
          findsOneWidget,
        );
        expect(
          find.textContaining(RegExp('old-category', caseSensitive: false)),
          findsNothing,
        );
        expect(
          find.textContaining(RegExp('gone-category', caseSensitive: false)),
          findsNothing,
        );
      },
      ready: _readyBefore(),
    );

    testSession('a left guild leaves the rail', (tester, session) async {
      expect(_spaceRow(_leftGuildId), findsOneWidget);

      await _identifyAgain(session, _readyAfter());

      expect(_spaceRow(_leftGuildId), findsNothing);
      expect(_spaceRow(_guildId), findsOneWidget);
    }, ready: _readyBefore());

    // READY lists DMs newest first, and each gained one goes on top in turn.
    testSession('gained DMs go above the ones already held', (
      tester,
      session,
    ) async {
      await _identifyAgain(session, _readyAfter());

      expect(_rowsTopToBottom(tester, _dms), [
        _gainedDmA,
        _gainedDmB,
        _dmChannelId,
      ]);
    }, ready: _readyBefore());

    testSession(
      'a changed channel keeps the unread mark it had on screen',
      (tester, session) async {
        await session.dispatch(
          'MESSAGE_CREATE',
          rawMessage(
            id: '900000000000000001',
            channelId: _secondId,
            guildId: _guildId,
            authorId: SessionHarness.friendId,
            content: 'new while the channel is closed',
          ),
        );

        await _identifyAgain(session, _readyAfter());

        final channel = _chat(tester).workspace!.channelOrNull(_secondId)!;
        expect(channel.name, 'renamed');
        expect(channel.unread, isTrue);
      },
      ready: _readyBefore(),
    );

    testSession(
      'an offline launch finds what the reconnect wrote',
      (tester, session) async {
        await _identifyAgain(session, _readyAfter());

        await session.relaunchUnreachable();
        await _showSpace(tester, session, _guildId);

        expect(_spaceRow(_leftGuildId), findsNothing);
        expect(_rowsTopToBottom(tester, _guildChannels), [
          _firstId,
          _secondId,
          _thirdId,
          _gainedId,
        ]);
        expect(
          find.descendant(
            of: _channelRow(_secondId),
            matching: find.text('renamed'),
          ),
          findsOneWidget,
        );
      },
      ready: _readyBefore(),
      onDisk: true,
    );

    testSession(
      'an offline launch shows the DMs in the order they had, after one changed',
      (tester, session) async {
        final before = _rowsTopToBottom(tester, _dms);
        expect(before, [_gainedDmB, _gainedDmA, _dmChannelId]);

        final ready = _withGainedDms(SessionHarness.defaultReady());
        ready['private_channels'] = [
          ...(ready['private_channels']! as List).take(2),
          _dm(_gainedDmB, _friendB, lastMessageId: '900000000000000009'),
        ];
        await _identifyAgain(session, ready);
        expect(_rowsTopToBottom(tester, _dms), before);

        await session.relaunchUnreachable();

        expect(_rowsTopToBottom(tester, _dms), before);
      },
      ready: _withGainedDms(SessionHarness.defaultReady()),
      onDisk: true,
    );
  });
}
