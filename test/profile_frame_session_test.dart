import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// FLUCORD-108: a profile frame draws around the profile card, reaching past
// its edges as Discord's does.

const _messageId = '900000000000000081';
const _profilePath = '/api/v9/users/${SessionHarness.friendId}/profile';
const _shopPath = '/api/v9/storefront/products/skus';

const _frameSku = '100000000000000401';
const _topLayer = '100000000000000411';
const _bottomLayer = '100000000000000412';
const _shop = 'https://cdn.discordapp.com/media/v1/collectibles-shop';

final _card = find.byKey(const ValueKey('profile-card'));

/// The shop's answer for the frame, shaped as a capture of Discord's.
Map<String, Object?> _products() => {
  'products': [
    {
      'sku_id': _frameSku,
      'name': 'Dark Roses',
      'items': [
        {
          'type': 3,
          'sku_id': _frameSku,
          'label': 'Roses on two corners',
          'layers': [
            {
              'id': _topLayer,
              'type': 'staple',
              'order': 'front',
              'anchor': 'top',
              'responsive': false,
            },
            {
              'id': _bottomLayer,
              'type': 'staple',
              'order': 'front',
              'anchor': 'bottom',
              'responsive': false,
            },
          ],
          'inner_width': 1200,
          'overflow_top': 211,
          'overflow_bottom': 186,
          'overflow_horizontal': 56,
        },
      ],
    },
  ],
};

/// The profile route with [collectibles] on the user profile, and the shop.
void Function(FakeDiscordTransport) _routes({
  List<Object?> collectibles = const [],
  bool shopFails = false,
}) =>
    (transport) => transport
      ..on(
        'GET',
        _shopPath,
        (_) => shopFails
            ? jsonResponse({'message': 'Unknown SKU'}, statusCode: 404)
            : jsonResponse(_products()),
      )
      ..on(
        'GET',
        _profilePath,
        (_) => jsonResponse({
          'user': {'id': SessionHarness.friendId, 'username': 'friend'},
          'user_profile': {'collectibles': collectibles},
        }),
      );

Map<String, Object?> _frame({int? expiresAt}) => {
  'sku_id': _frameSku,
  'type': 3,
  'expires_at': expiresAt,
};

/// Opens the friend's card from a message of theirs in the server.
Future<void> _openCard(WidgetTester tester, SessionHarness session) async {
  await session.openChannel(SessionHarness.channelId);
  await session.dispatch(
    'MESSAGE_CREATE',
    rawMessage(
      id: _messageId,
      channelId: SessionHarness.channelId,
      guildId: SessionHarness.guildId,
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
  expect(_card, findsOneWidget);
}

final _frontLayers = find.descendant(
  of: find.byKey(const ValueKey('profile-frame-front')),
  matching: find.byType(Image),
);

/// The frame picture that loads [layerId].
Finder _layer(String layerId) => find.descendant(
  of: find.byKey(const ValueKey('profile-frame-front')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        (widget.image as NetworkImage).url ==
            '$_shop/$_frameSku/$layerId/static',
  ),
);

void main() {
  testSession(
    'draws the frame around the card, scaled to it and reaching past it',
    (tester, session) async {
      await _openCard(tester, session);

      final card = tester.getRect(_card);
      final scale = card.width / 1200;
      final top = tester.getRect(_layer(_topLayer));
      final bottom = tester.getRect(_layer(_bottomLayer));
      // Both pictures are the card plus the side overhang wide.
      for (final picture in [top, bottom]) {
        expect(picture.left, moreOrLessEquals(card.left - 56 * scale));
        expect(picture.right, moreOrLessEquals(card.right + 56 * scale));
      }
      expect(top.top, moreOrLessEquals(card.top - 211 * scale));
      expect(bottom.bottom, moreOrLessEquals(card.bottom + 186 * scale));

      expect(
        session.transport.requests
            .singleWhere((request) => request.uri.path == _shopPath)
            .uri
            .queryParametersAll['sku_ids'],
        [_frameSku],
      );
    },
    routes: _routes(collectibles: [_frame()]),
  );

  testSession(
    'the popout keeps the whole frame on screen',
    (tester, session) async {
      await _openCard(tester, session);

      // The card opens by a message at the window's bottom edge.
      final window = MediaQuery.sizeOf(tester.element(_card));
      final frame = tester
          .getRect(_layer(_topLayer))
          .expandToInclude(tester.getRect(_layer(_bottomLayer)));
      expect(frame.top, greaterThanOrEqualTo(8));
      expect(frame.bottom, lessThanOrEqualTo(window.height - 8 + 0.01));
      expect(frame.right, lessThanOrEqualTo(window.width - 8 + 0.01));
    },
    routes: _routes(collectibles: [_frame()]),
  );

  testSession(
    'an expired frame is not drawn and never asks the shop',
    (tester, session) async {
      await _openCard(tester, session);

      expect(_frontLayers, findsNothing);
      expect(
        session.transport.requests.where(
          (request) => request.uri.path == _shopPath,
        ),
        isEmpty,
      );
    },
    // 2001-09-09, long gone.
    routes: _routes(collectibles: [_frame(expiresAt: 1000000000)]),
  );

  testSession(
    'a frame the shop cannot describe leaves the card as it is',
    (tester, session) async {
      await _openCard(tester, session);

      expect(_frontLayers, findsNothing);
    },
    routes: _routes(collectibles: [_frame()], shopFails: true),
  );

  testSession(
    'a profile with only an effect draws no frame and never asks the shop',
    (tester, session) async {
      await _openCard(tester, session);

      expect(_frontLayers, findsNothing);
      expect(
        session.transport.requests.where(
          (request) => request.uri.path == _shopPath,
        ),
        isEmpty,
      );
    },
    routes: _routes(
      collectibles: [
        {'sku_id': '100000000000000402', 'type': 1, 'expires_at': null},
      ],
    ),
  );
}
