import 'package:flucord/src/application/account_connections_controller.dart';
import 'package:flucord/src/domain/account_connections.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/presentation/widgets/oauth_connected_account_directory.dart';
import 'package:flucord/src/presentation/widgets/profile_card.dart';
import 'package:flucord/src/presentation/widgets/profile_card_data.dart';
import 'package:flucord/src/presentation/widgets/user_settings_connections_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

// FLUCORD-98: every connection draws its service's own logo, the same in
// the profile, the connection settings and the OAuth list.

/// Every connection type Discord has, as it names them on the wire.
const _discordTypes = [
  'amazon-music',
  'battlenet',
  'bluesky',
  'bungie',
  'crunchyroll',
  'domain',
  'ebay',
  'epicgames',
  'facebook',
  'github',
  'instagram',
  'leagueoflegends',
  'mastodon',
  'paypal',
  'playstation',
  'reddit',
  'riotgames',
  'roblox',
  'skype',
  'spotify',
  'steam',
  'tiktok',
  'twitch',
  'twitter',
  'xbox',
  'youtube',
];

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _host(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1280, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

/// Checks that each row draws one picture that loads, that no row falls
/// back to a letter, and that no two services share a picture.
Future<void> _expectOwnLogos(
  WidgetTester tester,
  Map<String, Finder> rows,
) async {
  final drawings = <String, String>{};
  for (final MapEntry(key: type, value: row) in rows.entries) {
    expect(row, findsOneWidget, reason: type);
    final picture = find.descendant(of: row, matching: find.byType(SvgPicture));
    expect(picture, findsWidgets, reason: type);
    final loader = tester.widget<SvgPicture>(picture.first).bytesLoader;
    final bytes = await tester.runAsync(() => loader.loadBytes(null));
    expect(bytes!.lengthInBytes, greaterThan(0), reason: type);
    drawings[type] = String.fromCharCodes(bytes.buffer.asUint8List());
    final letters = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data?.length ?? 0) == 1,
      ),
    );
    expect(letters, findsNothing, reason: type);
  }
  expect(drawings.values.toSet(), hasLength(rows.length));
}

void main() {
  testWidgets('the full profile draws each service with its logo', (
    tester,
  ) async {
    await _host(
      tester,
      SizedBox(
        height: 3800,
        child: FullProfile(
          data: ProfileCardData(
            userId: '100000000000000002',
            displayName: 'Freez',
            monogram: 'F',
            connections: [
              for (final type in _discordTypes)
                ProfileConnection(type: type, name: 'freez'),
            ],
          ),
        ),
      ),
    );

    await _expectOwnLogos(tester, {
      for (final type in _discordTypes) type: _key('profile-connection-$type'),
    });
  });

  testWidgets('services Flucord just learned read by their own names', (
    tester,
  ) async {
    await _host(
      tester,
      FullProfile(
        data: const ProfileCardData(
          userId: '100000000000000002',
          displayName: 'Freez',
          monogram: 'F',
          connections: [
            ProfileConnection(type: 'paypal', name: 'payer'),
            ProfileConnection(type: 'amazon-music', name: 'listener'),
          ],
        ),
      ),
    );

    expect(find.bySemanticsLabel('PayPal: payer'), findsOneWidget);
    expect(find.bySemanticsLabel('Amazon Music: listener'), findsOneWidget);
  });

  testWidgets('the connection settings draw each service with its logo', (
    tester,
  ) async {
    final repository = _Connections([
      for (final type in _discordTypes)
        AccountConnection(id: 'id-$type', type: type, name: 'freez'),
    ]);
    final controller = AccountConnectionsController(
      () => repository,
      launcher: _Launcher(),
    );
    addTearDown(controller.dispose);
    await _host(
      tester,
      SingleChildScrollView(
        child: ConnectionsSettingsSection(controller: controller),
      ),
    );

    await _expectOwnLogos(tester, {
      for (final type in _discordTypes)
        type: _key('connection-$type-id-$type'),
    });
  });

  testWidgets('the OAuth list draws each service with its logo', (
    tester,
  ) async {
    await _host(
      tester,
      SingleChildScrollView(
        child: OAuthConnectedAccountDirectory(
          connections: [
            for (final type in _discordTypes)
              DiscordOAuthConnection(id: 'id-$type', name: 'freez', type: type),
          ],
        ),
      ),
    );

    await _expectOwnLogos(tester, {
      for (final type in _discordTypes)
        type: _key('discord-oauth-connection-$type-id-$type'),
    });
  });
}

final class _Connections implements AccountConnectionsRepository {
  _Connections(this.connections);

  final List<AccountConnection> connections;

  @override
  Future<List<AccountConnection>> loadConnections() async => connections;

  @override
  Future<String?> startLink(String type) async => null;

  @override
  Future<void> unlink(AccountConnection connection) async {}
}

final class _Launcher implements ExternalLinkLauncher {
  @override
  Future<bool> open(Uri uri) async => true;
}
