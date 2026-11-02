import 'dart:async';

import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/presentation/widgets/chat_scope.dart';
import 'package:flucord/src/presentation/widgets/status_views.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

/// The most messages a channel that is not open may hold.
const _cap = 200;

/// One page of history, as the desktop transport asks for it.
const _pageSize = 100;

const _openChannelPath =
    '/api/v9/channels/${SessionHarness.channelId}/messages';

String _idOf(int index) => '9${index.toString().padLeft(17, '0')}';

/// Message [index] in [channelId]. A larger index is a newer id and a later time.
Map<String, Object?> _message(
  int index, {
  String channelId = SessionHarness.channelId,
}) => rawMessage(
  id: _idOf(index),
  channelId: channelId,
  guildId: SessionHarness.guildId,
  authorId: SessionHarness.friendId,
  content: 'Message $index',
  timestamp: DateTime.utc(
    2026,
    7,
    20,
  ).add(Duration(minutes: index)).toIso8601String(),
);

/// A page as Discord answers it, newest first.
List<Map<String, Object?>> _page(int first, int count) => [
  for (var index = first + count - 1; index >= first; index--) _message(index),
];

List<String> _idsFrom(int first, int count) => [
  for (var index = first; index < first + count; index++) _idOf(index),
];

/// Sends messages [first] up to, and not including, [end] into [channelId].
Future<void> _arrive(
  SessionHarness session,
  int first,
  int end, {
  String channelId = SessionHarness.channelId,
}) async {
  for (var index = first; index < end; index++) {
    await session.dispatch(
      'MESSAGE_CREATE',
      _message(index, channelId: channelId),
      settle: false,
    );
  }
  await session.settle();
}

ChatController _chat(WidgetTester tester) =>
    tester.widget<ChatScope>(find.byType(ChatScope)).notifier!;

List<String> _heldIds(WidgetTester tester, String channelId) => [
  for (final message in _chat(tester).workspace!.messagesFor(channelId))
    message.id,
];

// Newest-page requests only. A window around the read cursor (FLUCORD-22) is
// not a first page.
int _firstPageRequests(SessionHarness session) => session.transport.requests
    .where(
      (request) =>
          request.method == 'GET' &&
          request.uri.path == _openChannelPath &&
          !request.uri.queryParameters.containsKey('before') &&
          !request.uri.queryParameters.containsKey('around'),
    )
    .length;

void main() {
  testSession('messages arriving in a channel not open stop at the cap', (
    tester,
    session,
  ) async {
    await session.openChannel(SessionHarness.channelId);

    await _arrive(
      session,
      0,
      _cap + 50,
      channelId: SessionHarness.otherChannelId,
    );

    expect(
      _heldIds(tester, SessionHarness.otherChannelId),
      _idsFrom(50, _cap),
      reason: 'the newest messages stay, in order',
    );
  });

  testSession('the open channel has no cap', (tester, session) async {
    await session.openChannel(SessionHarness.channelId);

    await _arrive(session, 0, _cap + 10);

    expect(_heldIds(tester, SessionHarness.channelId), hasLength(_cap + 10));
  });

  testSession(
    'leaving a channel caps it, and opening it loads its history again',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _arrive(session, _pageSize, _cap + 50);
      expect(_firstPageRequests(session), 1);

      await session.openChannel(SessionHarness.otherChannelId);
      expect(_heldIds(tester, SessionHarness.channelId), hasLength(_cap));

      session.transport.on(
        'GET',
        _openChannelPath,
        (_) => jsonResponse(_page(_cap + 50 - _pageSize, _pageSize)),
      );
      await session.openChannel(SessionHarness.channelId);

      expect(_firstPageRequests(session), 2);
      expect(session.messageRow(_idOf(_cap + 49)), findsOneWidget);
      expect(
        _heldIds(tester, SessionHarness.channelId),
        _idsFrom(_cap + 50 - _pageSize, _pageSize),
      );
    },
    routes: (transport) => transport.on(
      'GET',
      _openChannelPath,
      (_) => jsonResponse(_page(0, _pageSize)),
    ),
  );

  testSession(
    'a channel that stayed under the cap opens with no new request',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await session.openChannel(SessionHarness.otherChannelId);

      await session.openChannel(SessionHarness.channelId);

      expect(_firstPageRequests(session), 1);
      expect(session.messageRow(_idOf(_pageSize - 1)), findsOneWidget);
    },
    routes: (transport) => transport.on(
      'GET',
      _openChannelPath,
      (_) => jsonResponse(_page(0, _pageSize)),
    ),
  );

  testSession(
    'a channel capped while unread opens with its NEW line on a held message',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await session.openChannel(SessionHarness.otherChannelId);
      await _arrive(session, 0, _cap + 50);

      session.transport.on(
        'GET',
        _openChannelPath,
        (_) => jsonResponse(_page(_cap + 50 - _pageSize, _pageSize)),
      );
      await session.openChannel(SessionHarness.channelId);

      expect(find.byType(ChannelLoadingView), findsNothing);
      expect(_firstPageRequests(session), 2);
      expect(
        find.byKey(const ValueKey('unread-message-boundary')),
        findsOneWidget,
      );
    },
    routes: (transport) =>
        transport.on('GET', _openChannelPath, (_) => jsonResponse(const [])),
  );

  testSession(
    'a channel with a read cursor, capped while unread, opens on its NEW line',
    (tester, session) async {
      await session.openChannel(SessionHarness.otherChannelId);
      await _arrive(session, 1, _cap + 50);
      expect(_heldIds(tester, SessionHarness.channelId), hasLength(_cap));

      session.transport.on(
        'GET',
        _openChannelPath,
        (_) => jsonResponse(_page(_cap + 50 - _pageSize, _pageSize)),
      );
      await session.openChannel(SessionHarness.channelId);

      expect(find.byType(ChannelLoadingView), findsNothing);
      expect(_firstPageRequests(session), 2);
      expect(
        find.byKey(const ValueKey('unread-message-boundary')),
        findsOneWidget,
      );
    },
    routes: (transport) =>
        transport.on('GET', _openChannelPath, (_) => jsonResponse(const [])),
    ready: {
      ...SessionHarness.defaultReady(),
      'guilds': [
        rawGuild(
          id: SessionHarness.guildId,
          name: 'The Forge',
          channels: [
            rawChannel(
              id: SessionHarness.channelId,
              name: 'general',
              lastMessageId: _idOf(0),
            ),
            rawChannel(id: SessionHarness.otherChannelId, name: 'random'),
          ],
          everyonePermissions: '${DiscordPermissions.viewChannel}',
        ),
      ],
      'read_state': {
        'version': 1,
        'partial': false,
        'entries': [
          {'id': SessionHarness.channelId, 'last_message_id': _idOf(0)},
        ],
      },
    },
  );

  final olderPage = Completer<void>();
  testSession(
    'an older page that lands after the reader left stays under the cap',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);
      await _arrive(session, 2 * _pageSize, _cap + _pageSize);
      expect(_heldIds(tester, SessionHarness.channelId), hasLength(_cap));

      unawaited(_chat(tester).loadOlderMessages(SessionHarness.channelId));
      await session.settle();
      await session.openChannel(SessionHarness.otherChannelId);
      olderPage.complete();
      await session.settle();

      expect(
        _heldIds(tester, SessionHarness.channelId),
        _idsFrom(_pageSize, _cap),
      );

      await session.openChannel(SessionHarness.channelId);

      expect(_firstPageRequests(session), 2);
    },
    routes: (transport) =>
        transport.on('GET', _openChannelPath, (request) async {
          if (!request.uri.queryParameters.containsKey('before')) {
            return jsonResponse(_page(_pageSize, _pageSize));
          }
          await olderPage.future;
          return jsonResponse(_page(0, _pageSize));
        }),
  );
}
