import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/presentation/widgets/oauth_guild_rail.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final account = DiscordOAuthAccount(
    id: 'user-1',
    username: 'jack',
    displayName: 'Jack',
    guilds: [
      DiscordOAuthGuild(id: 'guild-1', name: 'The Forge'),
      DiscordOAuthGuild(id: 'guild-2', name: 'Night Shift'),
    ],
  );

  Future<void> pumpRail(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: OAuthGuildRail(
          account: account,
          accountHomeSelected: false,
          selectedGuildId: 'guild-1',
          onOpenAccountHome: () {},
          onSelectGuild: (_) {},
          onOpenConnections: () {},
          onToggleTheme: () {},
          isDark: true,
        ),
      ),
    ),
  );

  testWidgets('the OAuth rail matches the server rail', (tester) async {
    await pumpRail(tester);

    final rail = tester.getRect(find.byKey(const ValueKey('oauth-guild-rail')));
    expect(rail.width, 64);
    for (final key in [
      'oauth-account-home',
      'oauth-guild-guild-1',
      'oauth-guild-guild-2',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))),
        const Size(40, 40),
        reason: key,
      );
    }

    final pill = tester.getRect(
      find.byKey(const ValueKey('oauth-guild-indicator-guild-1')),
    );
    expect(pill.height, 20);
    expect(pill.left, rail.left);
  });
}
