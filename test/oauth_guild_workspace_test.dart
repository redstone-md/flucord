import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/oauth_guild_directory_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/presentation/widgets/oauth_guild_workspace.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('keeps guild navigation and message boundary on compact width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = DiscordOAuthAccount(
      id: 'user-1',
      username: 'jack',
      displayName: 'Jack',
      guilds: [
        DiscordOAuthGuild(id: 'guild-1', name: 'The Forge'),
        DiscordOAuthGuild(id: 'guild-2', name: 'Night Shift'),
      ],
    );
    final controller = OAuthGuildDirectoryController()..reconcile(account);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => OAuthGuildWorkspace(
            account: account,
            selectedGuildId: controller.selectedGuildId,
            onSelectGuild: (guildId) =>
                controller.selectGuild(account, guildId),
            onOpenConnections: () {},
            onToggleTheme: () {},
            isDark: true,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('oauth-guild-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('oauth-guild-sidebar')), findsNothing);
    expect(
      find.byKey(const ValueKey('oauth-guild-message-boundary')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('oauth-guild-guild-2')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('oauth-guild-indicator-guild-2')),
      findsOneWidget,
    );
    expect(find.text('Night Shift'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
