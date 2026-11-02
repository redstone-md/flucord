import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/presentation/widgets/streamer_mode_scope.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000001';
const _laterMessageId = '900000000000000002';
const _categoryId = '800000000000000001';
const _friend = {
  'id': SessionHarness.friendId,
  'username': 'friend',
  'global_name': 'Friend',
};

/// What a screen reader gets for the widget with this key.
SemanticsNode _announced(WidgetTester tester, String key) =>
    tester.getSemantics(find.byKey(ValueKey(key)));

/// A message in a channel the reader is not looking at.
Map<String, Object?> _elsewhere(String id, {bool mentionsMe = false}) => {
  ...rawMessage(
    id: id,
    channelId: SessionHarness.otherChannelId,
    guildId: SessionHarness.guildId,
    authorId: SessionHarness.friendId,
    content: 'hello',
  ),
  if (mentionsMe)
    'mentions': [
      {'id': SessionHarness.currentUserId, 'username': 'me'},
    ],
};

/// The default account, with its channels under one category.
Map<String, Object?> _readyWithCategory() => {
  ...SessionHarness.defaultReady(),
  'guilds': [
    rawGuild(
      id: SessionHarness.guildId,
      name: 'The Forge',
      channels: [
        {...rawChannel(id: _categoryId, name: 'Text channels'), 'type': 4},
        {
          ...rawChannel(id: SessionHarness.channelId, name: 'general'),
          'parent_id': _categoryId,
        },
      ],
    ),
  ],
};

/// Presses Tab until the node for [target] holds the focus, as a keyboard user
/// does. Fails if a whole lap of the window never lands there.
Future<void> _tabTo(
  WidgetTester tester,
  SessionHarness session,
  Finder target,
) async {
  for (var press = 0; press < 100; press++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await session.settle();
    if (target.evaluate().isNotEmpty && _isFocused(tester, target)) return;
  }
  fail('Tab never reached $target');
}

/// The first choice the emoji picker offers.
final _anyEmoji = find
    .byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('emoji-choice-'),
    )
    .first;

/// Opens the channel on one message from [authorId].
Future<void> _openWithMessage(SessionHarness session, String authorId) async {
  await session.openChannel(SessionHarness.channelId);
  await session.dispatch('MESSAGE_CREATE', {
    ...rawMessage(
      id: _messageId,
      channelId: SessionHarness.channelId,
      guildId: SessionHarness.guildId,
      authorId: authorId,
      content: 'hello',
    ),
    if (authorId == SessionHarness.friendId) 'author': _friend,
  });
}

bool _isFocused(WidgetTester tester, Finder target) => isSemantics(
  isFocused: true,
).matches(tester.getSemantics(target), <Object?, Object?>{});

void main() {
  group('a channel row', () {
    testSession('announces that it is selected', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      expect(
        _announced(tester, 'channel-${SessionHarness.channelId}'),
        isSemantics(
          label: 'general',
          isButton: true,
          isSelected: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );
      expect(
        _announced(tester, 'channel-${SessionHarness.otherChannelId}'),
        isSemantics(label: 'random', isSelected: false),
      );
    });

    testSession('announces unread messages', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      await session.dispatch('MESSAGE_CREATE', _elsewhere(_messageId));

      expect(
        _announced(tester, 'channel-${SessionHarness.otherChannelId}'),
        isSemantics(label: 'random, unread'),
      );
    });

    testSession('announces how many mentions wait', (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      await session.dispatch(
        'MESSAGE_CREATE',
        _elsewhere(_messageId, mentionsMe: true),
      );
      expect(
        _announced(tester, 'channel-${SessionHarness.otherChannelId}'),
        isSemantics(label: 'random, 1 mention'),
      );

      await session.dispatch(
        'MESSAGE_CREATE',
        _elsewhere('900000000000000002', mentionsMe: true),
      );
      expect(
        _announced(tester, 'channel-${SessionHarness.otherChannelId}'),
        isSemantics(label: 'random, 2 mentions'),
      );
    });
  });

  testSession('a category announces whether it is expanded', (
    tester,
    session,
  ) async {
    await tester.tap(
      find.byKey(const ValueKey('space-${SessionHarness.guildId}')),
    );
    await session.settle();

    expect(
      _announced(tester, 'category-$_categoryId'),
      isSemantics(
        label: 'Text channels',
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('category-$_categoryId')));
    await session.settle();

    expect(
      _announced(tester, 'category-$_categoryId'),
      isSemantics(hasExpandedState: true, isExpanded: false),
    );
  }, ready: _readyWithCategory());

  group('a message row', () {
    testSession(
      'takes keyboard focus and announces author, time and text',
      (tester, session) async {
        await session.openChannel(SessionHarness.channelId);
        await session.dispatch('MESSAGE_CREATE', {
          ...rawMessage(
            id: _messageId,
            channelId: SessionHarness.channelId,
            guildId: SessionHarness.guildId,
            authorId: SessionHarness.friendId,
            content: 'hello <@${SessionHarness.friendId}>',
            timestamp: '2026-07-25T12:00:00+00:00',
          ),
          'author': _friend,
        });

        await _tabTo(tester, session, session.messageRow(_messageId));

        final row = tester.getSemantics(session.messageRow(_messageId));
        expect(
          row.label,
          matches(
            r'^Friend, Saturday, July 25, 2026 at \d\d:\d\d, hello @Friend$',
          ),
        );
        expect(row, isSemantics(isFocusable: true));
      },
      platform: TargetPlatform.windows,
    );

    testSession('does not read out an invite link in streamer mode', (
      tester,
      session,
    ) async {
      await session.openChannel(SessionHarness.channelId);
      await session.dispatch(
        'MESSAGE_CREATE',
        rawMessage(
          id: _messageId,
          channelId: SessionHarness.channelId,
          guildId: SessionHarness.guildId,
          authorId: SessionHarness.friendId,
          content: 'join discord.gg/secret',
        ),
      );

      final streamerMode = StreamerModeScope.maybeOf(
        tester.element(session.messageRow(_messageId)),
      )!;
      await tester.runAsync(() => streamerMode.setEnabled(enabled: true));
      await session.settle();

      expect(
        tester.getSemantics(session.messageRow(_messageId)).label,
        isNot(contains('discord.gg/secret')),
      );
    });

    testSession(
      'shows a visible ring and its actions only while it holds the focus',
      (tester, session) async {
        await _openWithMessage(session, SessionHarness.friendId);
        final ring = find.byKey(const ValueKey('message-focus-ring'));
        expect(ring, findsNothing);
        expect(find.byTooltip('Reply'), findsNothing);
        expect(_isFocused(tester, session.messageRow(_messageId)), isFalse);

        await _tabTo(tester, session, session.messageRow(_messageId));

        expect(ring, findsOneWidget);
        expect(find.byTooltip('Reply'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await session.settle();

        expect(ring, findsNothing);
        expect(find.byTooltip('Reply'), findsOneWidget);
      },
      platform: TargetPlatform.windows,
    );

    testSession(
      'Tab moves from one row to the next with no other stop',
      (tester, session) async {
        await _openWithMessage(session, SessionHarness.friendId);
        await session.dispatch(
          'MESSAGE_CREATE',
          rawMessage(
            id: _laterMessageId,
            channelId: SessionHarness.channelId,
            guildId: SessionHarness.guildId,
            authorId: SessionHarness.friendId,
            content: 'and again',
          ),
        );
        await _tabTo(tester, session, session.messageRow(_laterMessageId));

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await session.settle();

        expect(_isFocused(tester, session.messageRow(_messageId)), isTrue);
      },
      platform: TargetPlatform.windows,
    );

    testSession(
      'moves to the next row with the arrow keys',
      (tester, session) async {
        await _openWithMessage(session, SessionHarness.friendId);
        await session.dispatch(
          'MESSAGE_CREATE',
          rawMessage(
            id: _laterMessageId,
            channelId: SessionHarness.channelId,
            guildId: SessionHarness.guildId,
            authorId: SessionHarness.friendId,
            content: 'and again',
          ),
        );
        await _tabTo(tester, session, session.messageRow(_messageId));

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await session.settle();

        expect(_isFocused(tester, session.messageRow(_laterMessageId)), isTrue);
      },
      platform: TargetPlatform.windows,
    );

    testSession(
      'keeps its actions hidden after a click on its text',
      (tester, session) async {
        await _openWithMessage(session, SessionHarness.friendId);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tester.getCenter(find.text('hello')));
        await tester.pump();

        await mouse.down(tester.getCenter(find.text('hello')));
        await mouse.up();
        await session.settle();
        await mouse.moveTo(tester.getTopLeft(find.byType(MaterialApp)));
        await session.settle();
        await mouse.removePointer();

        expect(find.byTooltip('Reply'), findsNothing);
        expect(find.byKey(const ValueKey('message-focus-ring')), findsNothing);
      },
      platform: TargetPlatform.windows,
    );

    testSession('reaches reply with no pointer', (tester, session) async {
      await _openWithMessage(session, SessionHarness.friendId);
      await _tabTo(tester, session, session.messageRow(_messageId));

      await _tabTo(tester, session, find.byTooltip('Reply'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await session.settle();

      expect(find.text('Replying to Friend'), findsOneWidget);
    }, platform: TargetPlatform.windows);

    testSession(
      'reaches edit with no pointer, and gets the focus back after it',
      (tester, session) async {
        await _openWithMessage(session, SessionHarness.currentUserId);
        await _tabTo(tester, session, session.messageRow(_messageId));

        await _tabTo(tester, session, find.byTooltip('Edit'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await session.settle();

        final field = find.byKey(const ValueKey('edit-$_messageId'));
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await session.settle();

        expect(field, findsNothing);
        expect(_isFocused(tester, session.messageRow(_messageId)), isTrue);
      },
      platform: TargetPlatform.windows,
    );

    testSession('reaches react with no pointer', (tester, session) async {
      final grin =
          '/api/v9/channels/${SessionHarness.channelId}/messages/$_messageId'
          '/reactions/${Uri.encodeComponent('😀')}/@me';
      session.transport.on(
        'PUT',
        grin,
        (_) => jsonResponse(null, statusCode: 204),
      );
      await _openWithMessage(session, SessionHarness.friendId);
      await _tabTo(tester, session, session.messageRow(_messageId));

      final addReaction = find.byKey(
        const ValueKey('add-reaction-$_messageId'),
      );
      await _tabTo(tester, session, addReaction);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emoji-picker')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('emoji-search')),
        'grinning',
      );
      await session.settle();
      await _tabTo(tester, session, _anyEmoji);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await session.settle();

      expect(
        session.transport.requests.where(
          (request) => request.method == 'PUT' && request.uri.path == grin,
        ),
        hasLength(1),
      );
      expect(find.byKey(const ValueKey('emoji-picker')), findsNothing);
      expect(_isFocused(tester, addReaction), isTrue);
    }, platform: TargetPlatform.windows);
  });
}
