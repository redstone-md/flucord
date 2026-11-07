import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000001';
const _forwardId = '900000000000000002';
const _stickerMessageId = '900000000000000003';
const _stickerId = '600000000000000001';

const _generalPath = '/api/v9/channels/${SessionHarness.channelId}/messages';
const _randomPath =
    '/api/v9/channels/${SessionHarness.otherChannelId}/messages';

/// Forward, stickers and Suppress embeds, driven as a person on their own
/// account drives them: through the screen, down to the request Discord gets.
void main() {
  testSession('a forward goes to the chosen channel and its snapshot shows', (
    tester,
    session,
  ) async {
    final forward = {
      ...rawMessage(
        id: _forwardId,
        channelId: SessionHarness.otherChannelId,
        authorId: SessionHarness.currentUserId,
        content: '',
        guildId: SessionHarness.guildId,
      ),
      'message_reference': {
        'type': 1,
        'message_id': _messageId,
        'channel_id': SessionHarness.channelId,
        'guild_id': SessionHarness.guildId,
      },
      'message_snapshots': [
        {
          'message': {
            'content': 'Ship the slice',
            'timestamp': '2026-07-25T10:00:00+00:00',
          },
        },
      ],
    };
    // Discord answers the send with the forward, and has it in the channel's
    // history when the app goes there.
    session.transport
      ..on('POST', _randomPath, (_) => jsonResponse(forward))
      ..on('GET', _randomPath, (_) => jsonResponse([forward]));
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch(
      'MESSAGE_CREATE',
      rawMessage(
        id: _messageId,
        channelId: SessionHarness.channelId,
        authorId: SessionHarness.friendId,
        content: 'Ship the slice',
        guildId: SessionHarness.guildId,
      ),
    );

    await _hover(tester, session.messageRow(_messageId));
    await tester.tap(find.byKey(const ValueKey('forward-message-$_messageId')));
    await session.settle();
    await tester.tap(
      find.byKey(
        const ValueKey('message-forward-${SessionHarness.otherChannelId}'),
      ),
    );
    await session.settle();
    await tester.tap(find.byKey(const ValueKey('message-forward-submit')));
    await session.settle();

    final sent = session.transport.requests.lastWhere(
      (request) => request.method == 'POST' && request.uri.path == _randomPath,
    );
    expect((sent.json! as Map)['message_reference'], {
      'type': 1,
      'message_id': _messageId,
      'channel_id': SessionHarness.channelId,
    });
    expect(find.byKey(const ValueKey('forwarded-message')), findsOneWidget);
    expect(find.textContaining('Ship the slice'), findsOneWidget);
  });

  testSession('a sticker picked in the composer is sent', (
    tester,
    session,
  ) async {
    session.transport.on(
      'POST',
      _generalPath,
      (_) => jsonResponse({
        ...rawMessage(
          id: _stickerMessageId,
          channelId: SessionHarness.channelId,
          authorId: SessionHarness.currentUserId,
          content: '',
          guildId: SessionHarness.guildId,
        ),
        'sticker_items': [
          {'id': _stickerId, 'name': 'wave', 'format_type': 1},
        ],
      }),
    );
    await session.openChannel(SessionHarness.channelId);

    await tester.tap(find.byKey(const ValueKey('open-sticker-picker')));
    await session.settle();
    await tester.tap(find.byKey(const ValueKey('sticker-option-$_stickerId')));
    await session.settle();
    await tester.tap(find.byKey(const ValueKey('send-stickers')));
    await session.settle();

    final sent = session.transport.requests.lastWhere(
      (request) => request.method == 'POST' && request.uri.path == _generalPath,
    );
    expect((sent.json! as Map)['sticker_ids'], [_stickerId]);
    expect(session.messageRow(_stickerMessageId), findsOneWidget);
  }, ready: _readyWithSticker());

  testSession('Suppress embeds takes the preview off the account\'s message', (
    tester,
    session,
  ) async {
    Map<String, Object?> own({required int flags}) => {
      ...rawMessage(
        id: _messageId,
        channelId: SessionHarness.channelId,
        authorId: SessionHarness.currentUserId,
        content: 'https://example.com/release',
        guildId: SessionHarness.guildId,
      ),
      'flags': flags,
      'embeds': [
        if (flags == 0) {'type': 'rich', 'title': 'Preview title'},
      ],
    };
    session.transport.on(
      'PATCH',
      '$_generalPath/$_messageId',
      (_) => jsonResponse(own(flags: 4)),
    );
    await session.openChannel(SessionHarness.channelId);
    await session.dispatch('MESSAGE_CREATE', own(flags: 0));
    expect(find.text('Preview title'), findsOneWidget);

    await _hover(tester, session.messageRow(_messageId));
    await tester.tap(find.byKey(const ValueKey('suppress-embeds-$_messageId')));
    await session.settle();

    final sent = session.transport.requests.lastWhere(
      (request) => request.method == 'PATCH',
    );
    expect(sent.uri.path, '$_generalPath/$_messageId');
    expect(sent.json, {'flags': 4});
    expect(find.text('Preview title'), findsNothing);
  });
}

Future<void> _hover(WidgetTester tester, Finder row) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(row));
  await tester.pump();
}

/// The default READY, with one sticker in the server.
Map<String, Object?> _readyWithSticker() {
  final ready = SessionHarness.defaultReady();
  ready['guilds'] = [
    {
      ...rawGuild(
        id: SessionHarness.guildId,
        name: 'The Forge',
        channels: [rawChannel(id: SessionHarness.channelId, name: 'general')],
        everyonePermissions:
            '${DiscordPermissions.viewChannel | DiscordPermissions.sendMessages}',
      ),
      'stickers': [
        {'id': _stickerId, 'name': 'wave', 'format_type': 1, 'tags': 'hi'},
      ],
    },
  ];
  return ready;
}
