import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

const _messageId = '900000000000000001';
const _strangerId = '100000000000000003';
const _fire = '🔥';
const _rocket = '🚀';
const _messagePath =
    '/api/v9/channels/${SessionHarness.channelId}/messages/$_messageId';

String _reactionsPath(String emoji) =>
    '$_messagePath/reactions/${Uri.encodeComponent(emoji)}';

/// Who reacted, and super reactions, driven as a person on their own account
/// drives them: through the screen, down to the request Discord gets.
void main() {
  testSession(
    'the reaction list names who reacted, normal and super apart',
    (tester, session) async {
      session.transport.on(
        'GET',
        _reactionsPath(_fire),
        (request) => jsonResponse([
          if (request.uri.queryParameters['type'] == '1')
            {'id': _strangerId, 'username': 'omar', 'global_name': 'Omar'}
          else
            {
              'id': SessionHarness.friendId,
              'username': 'jack',
              'global_name': 'Jack',
            },
        ]),
      );
      await session.openChannel(SessionHarness.channelId);

      await _hover(tester, session.messageRow(_messageId));
      await tester.tap(
        find.byKey(const ValueKey('view-reactions-$_messageId')),
      );
      await session.settle();

      expect(find.text('Jack'), findsOneWidget);
      expect(find.text('Omar'), findsOneWidget);
      final omarRow = find.ancestor(
        of: find.text('Omar'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: omarRow.first, matching: find.text('Super')),
        findsOneWidget,
      );
      final jackRow = find.ancestor(
        of: find.text('Jack'),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(of: jackRow.first, matching: find.text('Super')),
        findsNothing,
      );
      expect(
        session.transport.requests
            .where((request) => request.uri.path == _reactionsPath(_fire))
            .map((request) => request.uri.queryParameters['type']),
        unorderedEquals(['0', '1']),
      );
    },
    routes: (transport) =>
        _routeHistory(transport, normal: 1, burst: 1, meBurst: false),
  );

  testSession(
    'a super reaction shows as its own chip, and a click takes it back',
    (tester, session) async {
      session.transport.on(
        'DELETE',
        '${_reactionsPath(_fire)}/1/@me',
        (_) => jsonResponse(null, statusCode: 204),
      );
      await session.openChannel(SessionHarness.channelId);

      expect(
        tester.getSemantics(_chip('$_fire reaction, 1')),
        isSemantics(hasToggledState: true, isToggled: false),
      );
      expect(
        tester.getSemantics(_chip('$_fire super reaction, 1')),
        isSemantics(hasToggledState: true, isToggled: true),
      );

      await tester.tap(_chip('$_fire super reaction, 1'));
      await session.settle();

      expect(
        session.transport.requests.where(
          (request) =>
              request.method == 'DELETE' &&
              request.uri.path == '${_reactionsPath(_fire)}/1/@me',
        ),
        hasLength(1),
      );
    },
    routes: (transport) {
      _routeHistory(transport, normal: 1, burst: 1, meBurst: true);
      _routeEntitlements(transport, nitro: true);
    },
  );

  testSession(
    'an account with Nitro adds a super reaction from the hover bar',
    (tester, session) async {
      final path = '${_reactionsPath(_rocket)}/@me';
      session.transport.on(
        'PUT',
        path,
        (_) => jsonResponse(null, statusCode: 204),
      );
      await session.openChannel(SessionHarness.channelId);

      await _hover(tester, session.messageRow(_messageId));
      await tester.tap(
        find.byKey(const ValueKey('add-super-reaction-$_messageId')),
      );
      await session.settle();
      await tester.enterText(
        find.byKey(const ValueKey('emoji-search')),
        'rocket',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('emoji-choice-unicode-rocket')),
      );
      await session.settle();

      final sent = session.transport.requests.where(
        (request) => request.method == 'PUT' && request.uri.path == path,
      );
      expect(sent.single.uri.queryParameters, {'type': '1'});
    },
    routes: (transport) {
      _routeHistory(transport, normal: 1, burst: 0, meBurst: false);
      _routeEntitlements(transport, nitro: true);
    },
  );

  testSession(
    'an account without Nitro is not offered a super reaction',
    (tester, session) async {
      await session.openChannel(SessionHarness.channelId);

      await _hover(tester, session.messageRow(_messageId));
      expect(
        find.byKey(const ValueKey('add-reaction-$_messageId')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('add-super-reaction-$_messageId')),
        findsNothing,
      );

      final sentBefore = session.transport.requests.length;
      await tester.tap(_chip('$_fire super reaction, 1'));
      await session.settle();
      expect(session.transport.requests, hasLength(sentBefore));
    },
    routes: (transport) {
      _routeHistory(transport, normal: 1, burst: 1, meBurst: false);
      _routeEntitlements(transport, nitro: false);
    },
  );
}

Finder _chip(String label) => find.bySemanticsLabel(label);

/// One message in the guild's first channel, with one 🔥 reaction.
void _routeHistory(
  FakeDiscordTransport transport, {
  required int normal,
  required int burst,
  required bool meBurst,
}) => transport.on(
  'GET',
  '/api/v9/channels/${SessionHarness.channelId}/messages',
  (_) => jsonResponse([
    {
      ...rawMessage(
        id: _messageId,
        channelId: SessionHarness.channelId,
        guildId: SessionHarness.guildId,
        authorId: SessionHarness.friendId,
        content: 'react to this',
      ),
      'reactions': [
        {
          'count': normal + burst,
          'count_details': {'normal': normal, 'burst': burst},
          'me': false,
          'me_burst': meBurst,
          'emoji': {'id': null, 'name': _fire},
          'burst_colors': ['#ff3366'],
        },
      ],
    },
  ]),
);

void _routeEntitlements(
  FakeDiscordTransport transport, {
  required bool nitro,
}) => transport.on(
  'GET',
  '/api/v9/users/@me/entitlements',
  (_) => jsonResponse([
    if (nitro)
      {
        'id': '700000000000000001',
        'type': 2,
        'sku': {'premium': true, 'name': 'Nitro'},
      },
  ]),
);

Future<void> _hover(WidgetTester tester, Finder row) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(row));
  await tester.pump();
}
