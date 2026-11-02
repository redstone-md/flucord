import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_user_settings_proto.dart';
import 'package:flucord/src/data/proto/proto_message.dart';
import 'package:flucord/src/presentation/widgets/server_rail.dart';

import 'support/fake_discord_wire.dart';
import 'support/session_harness.dart';

/// The rail's theme button, for an account that stores a theme and for one
/// that does not. Discord keeps the theme in the account settings, so the
/// button saves it there; it must not lose to the stored value.
void main() {
  const settingsPath = '/api/v9/users/@me/settings-proto/1';
  const darkOnWire = 1;
  const lightOnWire = 2;

  Brightness shown(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(ServerRail))).brightness;

  Iterable<RecordedRequest> saves(SessionHarness session) => session
      .transport
      .requests
      .where((r) => r.method == 'PATCH' && r.uri.path == settingsPath);

  int? savedTheme(RecordedRequest request) {
    final body = request.json! as Map<String, Object?>;
    return DiscordUserSettingsProto.decodeRoot(body['settings']! as String)
        .messageAt(PreloadedUserSettingsField.appearance)
        ?.varintAt(AppearanceField.theme);
  }

  Map<String, Object?> readyWithTheme(int theme) =>
      SessionHarness.defaultReady()
        ..['user_settings_proto'] = _storedTheme(theme);

  void echoSaves(FakeDiscordTransport transport) => transport.on(
    'PATCH',
    settingsPath,
    (request) => jsonResponse({
      'settings': (request.json! as Map<String, Object?>)['settings'],
    }),
  );

  testSession(
    'turns a stored dark theme light and saves it to the account',
    (tester, session) async {
      expect(shown(tester), Brightness.dark);

      await tester.tap(find.byTooltip('Use light theme'));
      await session.settle();

      expect(shown(tester), Brightness.light);
      expect(find.byTooltip('Use dark theme'), findsOneWidget);
      expect(saves(session).map(savedTheme), [lightOnWire]);
    },
    ready: readyWithTheme(darkOnWire),
    routes: echoSaves,
  );

  testSession(
    'offers dark when the stored theme is light, and switches to it',
    (tester, session) async {
      expect(shown(tester), Brightness.light);

      await tester.tap(find.byTooltip('Use dark theme'));
      await session.settle();

      expect(shown(tester), Brightness.dark);
      expect(saves(session).map(savedTheme), [darkOnWire]);
    },
    ready: readyWithTheme(lightOnWire),
    routes: echoSaves,
  );

  testSession('with no stored theme it switches locally and saves nothing', (
    tester,
    session,
  ) async {
    expect(shown(tester), Brightness.dark);

    await tester.tap(find.byTooltip('Use light theme'));
    await session.settle();

    expect(shown(tester), Brightness.light);
    expect(saves(session), isEmpty);
  });
}

String _storedTheme(int theme) => DiscordUserSettingsProto.encodeBase64(
  (ProtoMessage()..setMessage(
        PreloadedUserSettingsField.appearance,
        ProtoMessage()..setVarint(AppearanceField.theme, theme),
      ))
      .encode(),
);
