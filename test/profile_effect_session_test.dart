import 'package:flucord/src/domain/accessibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// FLUCORD-107: a profile effect plays over the profile card and the full
// profile, in Discord's order and timing. Discord's client reads how an
// effect looks from the shop's product, by the effect's SKU.

const _messageId = '900000000000000071';
const _profilePath = '/api/v9/users/${SessionHarness.friendId}/profile';

const _sakuraSku = '100000000000000301';
const _lanternSku = '100000000000000302';
const _effects = 'https://cdn.discordapp.com/assets/content';
const _sakuraIntro = '$_effects/sakura-intro';
const _sakuraLoop = '$_effects/sakura-loop';
const _sakuraStill =
    'https://cdn.discordapp.com/media/v1/collectibles-shop/sakura-still';
const _lanternLoop = '$_effects/lantern-loop';

String _productPath(String sku) => '/api/v9/collectibles-products/$sku';

/// A year after the test's clock would read, in Unix seconds.
final _future = DateTime.now().add(const Duration(days: 365));
int get _later => _future.millisecondsSinceEpoch ~/ 1000;

final _card = find.byKey(const ValueKey('profile-card'));
final _fullProfile = find.byKey(const ValueKey('full-profile'));

/// What `GET /collectibles-products/{sku}` answers for each effect, shaped
/// as a capture of Discord's.
final _products = <String, Map<String, Object?>>{
  _sakuraSku: {
    'sku_id': _sakuraSku,
    'name': 'Sakura',
    'type': 1,
    'items': [
      {
        'type': 1,
        'sku_id': _sakuraSku,
        'title': 'Sakura',
        'accessibilityLabel': 'Falling petals',
        'animationType': 2,
        'thumbnailPreviewSrc': '$_effects/sakura-thumbnail',
        'reducedMotionSrc': _sakuraStill,
        'effects': [
          {
            'src': _sakuraIntro,
            'loop': false,
            'height': 880,
            'width': 450,
            'duration': 2000,
            'start': 0,
            'loopDelay': 0,
            'position': {'x': 0, 'y': 0},
            'zIndex': 100,
            'randomizedSources': <Object?>[],
          },
          {
            'src': _sakuraLoop,
            'loop': true,
            'height': 880,
            'width': 450,
            'duration': 3000,
            'start': 2000,
            'loopDelay': 0,
            'position': {'x': 0, 'y': 0},
            'zIndex': 101,
            'randomizedSources': <Object?>[],
          },
        ],
      },
    ],
  },
  _lanternSku: {
    'sku_id': _lanternSku,
    'type': 1,
    'items': [
      {
        'type': 1,
        'sku_id': _lanternSku,
        'reducedMotionSrc': '$_effects/lantern-still',
        'effects': [
          {
            'src': _lanternLoop,
            'loop': true,
            'height': 880,
            'width': 450,
            'duration': 1000,
            'start': 0,
            'loopDelay': 0,
            'position': {'x': 0, 'y': 0},
            'zIndex': 100,
          },
        ],
      },
    ],
  },
};

/// [transport] with the shop's product route for each effect.
FakeDiscordTransport _withProducts(FakeDiscordTransport transport) {
  _products.forEach(
    (sku, product) =>
        transport.on('GET', _productPath(sku), (_) => jsonResponse(product)),
  );
  return transport;
}

/// The profile route with [userEffect] on the user profile and [serverEffect]
/// on the server profile, and the shop's effects.
void Function(FakeDiscordTransport) _routes({
  Map<String, Object?>? userEffect,
  Map<String, Object?>? serverEffect,
}) =>
    (transport) => _withProducts(transport)
      ..on('GET', _profilePath, (request) {
        final guildId = request.uri.queryParameters['guild_id'];
        return jsonResponse({
          'user': {'id': SessionHarness.friendId, 'username': 'friend'},
          'user_profile': {'profile_effect': ?userEffect},
          if (guildId != null)
            'guild_member_profile': {
              'guild_id': guildId,
              'profile_effect': ?serverEffect,
            },
        });
      });

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

/// The pictures the effect over [surface] draws now.
List<String> _layers(WidgetTester tester, Finder surface) => [
  for (final image in tester.widgetList<Image>(
    find.descendant(
      of: find.descendant(
        of: surface,
        matching: find.byKey(const ValueKey('profile-effect')),
      ),
      matching: find.byType(Image),
    ),
  ))
    (image.image as NetworkImage).url,
];

void main() {
  testSession(
    'plays the intro once over the card, then the loop',
    (tester, session) async {
      await _openCard(tester, session);
      expect(_layers(tester, _card), [_sakuraIntro]);

      await tester.pump(const Duration(seconds: 2));
      expect(_layers(tester, _card), [_sakuraLoop]);

      await tester.pump(const Duration(seconds: 10));
      expect(_layers(tester, _card), [_sakuraLoop]);
    },
    routes: _routes(userEffect: {'sku_id': _sakuraSku, 'expires_at': null}),
  );

  testSession(
    'plays over the full profile',
    (tester, session) async {
      await _openCard(tester, session);
      await tester.tap(find.byKey(const ValueKey('profile-card-avatar')));
      await session.settle();
      expect(_fullProfile, findsOneWidget);

      expect(_layers(tester, _fullProfile), [_sakuraIntro]);
      await tester.pump(const Duration(seconds: 2));
      expect(_layers(tester, _fullProfile), [_sakuraLoop]);
    },
    routes: _routes(userEffect: {'sku_id': _sakuraSku}),
  );

  testSession(
    "the server profile's effect replaces the user one in that server",
    (tester, session) async {
      await _openCard(tester, session);

      expect(_layers(tester, _card), [_lanternLoop]);
    },
    routes: _routes(
      userEffect: {'sku_id': _sakuraSku},
      serverEffect: {'sku_id': _lanternSku, 'expires_at': _later},
    ),
  );

  testSession(
    'reads each effect from the shop once for the session',
    (tester, session) async {
      await _openCard(tester, session);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await session.settle();

      await session.openChannel(
        SessionHarness.dmChannelId,
        space: 'direct-messages',
      );
      await session.dispatch(
        'MESSAGE_CREATE',
        rawMessage(
          id: '900000000000000072',
          channelId: SessionHarness.dmChannelId,
          authorId: SessionHarness.friendId,
          content: 'hi',
        ),
      );
      await tester.tap(
        find.descendant(
          of: session.messageRow('900000000000000072'),
          matching: find.byKey(const ValueKey('message-author-name')),
        ),
      );
      await session.settle();

      expect(_layers(tester, _card), [_sakuraIntro]);
      expect(
        session.transport.requests.where(
          (request) => request.uri.path == _profilePath,
        ),
        hasLength(2),
      );
      expect(
        session.transport.requests.where(
          (request) => request.uri.path == _productPath(_sakuraSku),
        ),
        hasLength(1),
      );
    },
    routes: _routes(userEffect: {'sku_id': _sakuraSku}),
  );

  testSession(
    'a profile without an effect draws none and never asks the shop',
    (tester, session) async {
      await _openCard(tester, session);

      expect(find.byKey(const ValueKey('profile-effect')), findsNothing);
      expect(
        session.transport.requests.where(
          (request) =>
              request.uri.path.startsWith('/api/v9/collectibles-products/'),
        ),
        isEmpty,
      );
    },
    routes: _routes(),
  );

  testSession(
    'an expired effect is not drawn',
    (tester, session) async {
      await _openCard(tester, session);

      expect(find.byKey(const ValueKey('profile-effect')), findsNothing);
    },
    // 2001-09-09, long gone.
    routes: _routes(
      userEffect: {'sku_id': _sakuraSku, 'expires_at': 1000000000},
    ),
  );

  testSession(
    'an effect that expires while the card is open goes away',
    (tester, session) async {
      await _openCard(tester, session);
      expect(find.byKey(const ValueKey('profile-effect')), findsOneWidget);

      await tester.pump(const Duration(minutes: 2));

      expect(find.byKey(const ValueKey('profile-effect')), findsNothing);
    },
    routes: _routes(
      userEffect: {
        'sku_id': _sakuraSku,
        // A minute from the real now: the card's clock is the real one.
        'expires_at':
            DateTime.now()
                .add(const Duration(minutes: 1))
                .millisecondsSinceEpoch ~/
            1000,
      },
    ),
  );

  testSession(
    "reduced motion draws Discord's still picture",
    (tester, session) async {
      await _openCard(tester, session);

      expect(_layers(tester, _card), [_sakuraStill]);
      await tester.pump(const Duration(seconds: 5));
      expect(_layers(tester, _card), [_sakuraStill]);
    },
    routes: _routes(userEffect: {'sku_id': _sakuraSku}),
    accessibility: const AccessibilitySettings(reducedMotion: true),
  );

  for (final (state, leave, back) in [
    ('unfocused', _blur, _focus),
    ('suspended', _minimize, _restore),
  ]) {
    testSession(
      'pauses while the window is $state, and goes on from there',
      (tester, session) async {
        await _openCard(tester, session);
        leave(session);
        await session.settle();

        await tester.pump(const Duration(seconds: 5));
        expect(_layers(tester, _card), [_sakuraIntro]);

        back(session);
        await session.settle();
        await tester.pump(const Duration(seconds: 2));
        expect(_layers(tester, _card), [_sakuraLoop]);
      },
      routes: _routes(userEffect: {'sku_id': _sakuraSku}),
    );
  }

  testSession(
    "the profile settings preview shows the account's own effect",
    (tester, session) async {
      await tester.tap(find.byKey(const ValueKey('account-settings')));
      await session.settle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-profile')));
      await session.settle();
      final preview = find.descendant(
        of: find.byKey(const ValueKey('settings-section-profile')),
        matching: _card,
      );

      expect(_layers(tester, preview), [_sakuraIntro]);
    },
    routes: (transport) => _withProducts(transport)
      ..on(
        'GET',
        '/api/v9/users/@me',
        (_) => jsonResponse({
          'id': SessionHarness.currentUserId,
          'username': 'me',
          'discriminator': '0',
        }),
      )
      ..on(
        'GET',
        '/api/v9/users/${SessionHarness.currentUserId}/profile',
        (_) => jsonResponse({
          'user': {'id': SessionHarness.currentUserId, 'username': 'me'},
          'user_profile': {
            'profile_effect': {'sku_id': _sakuraSku},
          },
        }),
      ),
  );
}

void _blur(SessionHarness session) => session.blurWindow();
void _focus(SessionHarness session) => session.focusWindow();
void _minimize(SessionHarness session) => session.minimizeWindow();
void _restore(SessionHarness session) => session.restoreWindow();
