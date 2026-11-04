import 'package:flucord/src/presentation/widgets/server_rail.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

// FLUCORD-105: a person's Nitro theme colours paint their profile, and the
// account's own colours can be set in the profile editor.

const _messageId = '900000000000000071';
const _roleId = '400000000000000071';
const _profilePath = '/api/v9/users/${SessionHarness.friendId}/profile';

// A deep indigo to violet, and a pale yellow to pink.
const _darkTheme = [0x1e1b4b, 0x4c1d95];
const _lightTheme = [0xfde68a, 0xfbcfe8];

final _card = find.byKey(const ValueKey('profile-card'));
final _cardTheme = find.descendant(
  of: _card,
  matching: find.byKey(const ValueKey('profile-card-theme')),
);

Finder _key(String key) => find.byKey(ValueKey(key));

/// The default READY, with the friend holding one role in The Forge, so
/// the card shows a role chip.
Map<String, Object?> _readyWithRole() {
  final ready = SessionHarness.defaultReady();
  final forge = (ready['guilds']! as List).first as Map<String, Object?>;
  forge['roles'] = [
    ...forge['roles']! as List,
    {'id': _roleId, 'name': 'Raider', 'color': 0, 'position': 1},
  ];
  forge['members'] = [
    {
      'user': {'id': SessionHarness.friendId, 'username': 'friend'},
      'roles': [_roleId],
      'joined_at': '2026-01-29T10:00:00+00:00',
    },
  ];
  return ready;
}

/// Whether [ink] shows lighter or darker than the top of the gradient
/// [theme] that it sits on.
Brightness Function(Color) _toneOn(List<int> theme) {
  final card = Color(0xff000000 | theme.first);
  return (ink) =>
      Color.alphaBlend(ink, card).computeLuminance() > card.computeLuminance()
      ? Brightness.light
      : Brightness.dark;
}

/// The colours of the card's text and of its role chip.
List<Color> _cardInk(WidgetTester tester) {
  final chip = _key('profile-card-role-$_roleId');
  return [
    tester.widget<Text>(_key('profile-card-handle')).style!.color!,
    tester
        .widget<Text>(find.descendant(of: chip, matching: find.byType(Text)))
        .style!
        .color!,
    (tester.widget<Container>(chip).decoration! as BoxDecoration).color!,
  ];
}

/// The profile route for the friend, with [serverProfile] for The Forge.
void Function(FakeDiscordTransport) _profileRoute({
  List<int>? themeColors,
  Map<String, Object?>? serverProfile,
}) =>
    (transport) => transport.on(
      'GET',
      _profilePath,
      (request) => jsonResponse({
        'user': {'id': SessionHarness.friendId, 'username': 'friend'},
        'user_profile': {'theme_colors': ?themeColors},
        if (serverProfile != null &&
            request.uri.queryParameters['guild_id'] == SessionHarness.guildId)
          'guild_member_profile': {
            'guild_id': SessionHarness.guildId,
            ...serverProfile,
          },
      }),
    );

Future<void> _openCard(WidgetTester tester, SessionHarness session) async {
  await session.openChannel(SessionHarness.channelId);
  if (session.messageRow(_messageId).evaluate().isEmpty) {
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
  }
  await tester.tap(
    find.descendant(
      of: session.messageRow(_messageId),
      matching: _key('message-author-name'),
    ),
  );
  await session.settle();
  expect(_card, findsOneWidget);
}

/// The gradient [theme] paints, top to bottom.
LinearGradient? _gradientIn(WidgetTester tester, Finder theme) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: theme, matching: find.byType(DecoratedBox)).first,
  );
  return (box.decoration as BoxDecoration).gradient as LinearGradient?;
}

void _expectGradient(WidgetTester tester, Finder theme, List<int> colours) {
  final gradient = _gradientIn(tester, theme)!;
  expect(gradient.colors, [for (final rgb in colours) Color(0xff000000 | rgb)]);
  expect(gradient.begin, Alignment.topCenter);
  expect(gradient.end, Alignment.bottomCenter);
}

/// The card's fill, its gradient and the colour of its handle line.
List<Object?> _cardLook(WidgetTester tester) => [
  tester
      .widget<Material>(
        find.descendant(of: _card, matching: find.byType(Material)).first,
      )
      .color,
  _gradientIn(tester, _cardTheme),
  tester.widget<Text>(_key('profile-card-handle')).style!.color,
];

/// The app's own colours, read where the card does not reach.
FlucordSurfaceTheme _appSurfaces(WidgetTester tester) =>
    tester.element(find.byType(ServerRail)).surfaces;

void main() {
  testSession(
    'switching Flucord to the light theme leaves a themed profile as it was',
    (tester, session) async {
      await _openCard(tester, session);
      final dark = _cardLook(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await session.settle();

      await tester.tap(find.byTooltip('Use light theme'));
      await session.settle();
      expect(
        Theme.of(tester.element(find.byType(ServerRail))).brightness,
        Brightness.light,
      );
      await _openCard(tester, session);

      expect(_cardLook(tester), dark);
    },
    routes: _profileRoute(themeColors: _darkTheme),
  );

  testSession(
    'a profile without theme colours keeps the app\'s colours',
    (tester, session) async {
      await _openCard(tester, session);

      final app = _appSurfaces(tester);
      expect(_cardLook(tester), [app.raised, null, app.muted]);
    },
    routes: _profileRoute(),
  );

  testSession(
    'theme colours paint the popout from primary at the top to accent below',
    (tester, session) async {
      await _openCard(tester, session);

      _expectGradient(tester, _cardTheme, _darkTheme);
    },
    routes: _profileRoute(themeColors: _darkTheme),
  );

  testSession(
    'theme colours paint the full profile\'s card the same way',
    (tester, session) async {
      await _openCard(tester, session);
      await tester.tap(_key('profile-card-name'));
      await session.settle();

      _expectGradient(tester, _key('full-profile-theme'), _darkTheme);
    },
    routes: _profileRoute(themeColors: _darkTheme),
  );

  testSession(
    'a server profile\'s theme colours replace the user profile\'s there',
    (tester, session) async {
      await _openCard(tester, session);

      _expectGradient(tester, _cardTheme, _lightTheme);
    },
    routes: _profileRoute(
      themeColors: _darkTheme,
      serverProfile: {'theme_colors': _lightTheme},
    ),
  );

  testSession(
    'text and chips are light on a dark gradient',
    (tester, session) async {
      await _openCard(tester, session);

      expect(
        _cardInk(tester).map(_toneOn(_darkTheme)),
        everyElement(Brightness.light),
      );
    },
    ready: _readyWithRole(),
    routes: _profileRoute(themeColors: _darkTheme),
  );

  testSession(
    'text and chips are dark on a light gradient',
    (tester, session) async {
      await _openCard(tester, session);

      expect(
        _cardInk(tester).map(_toneOn(_lightTheme)),
        everyElement(Brightness.dark),
      );
    },
    ready: _readyWithRole(),
    routes: _profileRoute(themeColors: _lightTheme),
  );
}
