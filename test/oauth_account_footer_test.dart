import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_social_presence_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_social_presence.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';
import 'package:flucord/src/presentation/widgets/discord_social_presence_scope.dart';
import 'package:flucord/src/presentation/widgets/oauth_account_footer.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('changes native status from the Discord-like account footer', (
    tester,
  ) async {
    final gateway = _PresenceGateway();
    final controller = DiscordSocialPresenceController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileSession(
      DiscordSocialSdkAvailability.ready,
      authenticated: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 236,
              child: DiscordSocialPresenceScope(
                controller: controller,
                child: OAuthAccountFooter(
                  account: DiscordOAuthAccount(
                    id: 'user-1',
                    username: 'jack',
                    displayName: 'Jack',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Online'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('discord-online-status-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('discord-online-status-doNotDisturb')),
    );
    await tester.pumpAndSettle();

    expect(gateway.statuses, [DiscordOnlineStatus.doNotDisturb]);
    expect(controller.status, DiscordOnlineStatus.doNotDisturb);
    expect(find.text('Do Not Disturb'), findsOneWidget);
  });

  testWidgets('keeps the linked identity footer inert without Social SDK', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 236,
            child: OAuthAccountFooter(
              account: DiscordOAuthAccount(
                id: 'user-1',
                username: 'jack',
                displayName: 'Jack',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('@jack'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('discord-online-status-menu')),
      findsNothing,
    );
  });
}

final class _PresenceGateway implements DiscordSocialPresenceGateway {
  final List<DiscordOnlineStatus> statuses = [];

  @override
  Future<void> setOnlineStatus(DiscordOnlineStatus status) async {
    statuses.add(status);
  }
}
