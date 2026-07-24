import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_social_sdk_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';
import 'package:flucord/src/presentation/widgets/discord_social_sdk_scope.dart';
import 'package:flucord/src/presentation/widgets/oauth_account_home.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('shows the absent native SDK in the Friends account home', (
    tester,
  ) async {
    final controller = await _controllerFor(
      DiscordSocialSdkAvailability.sdkNotBundled,
    );
    addTearDown(controller.dispose);

    await _pumpAccountHome(tester, controller);

    expect(find.text('Discord Social SDK is not bundled'), findsOneWidget);
    expect(find.textContaining('not routed through Bot API'), findsOneWidget);
  });

  testWidgets('shows a linked native SDK without claiming friend sync', (
    tester,
  ) async {
    final controller = await _controllerFor(DiscordSocialSdkAvailability.ready);
    addTearDown(controller.dispose);

    await _pumpAccountHome(tester, controller);

    expect(find.text('Native social access is linked'), findsOneWidget);
    expect(
      find.textContaining('friend synchronization are the next native step'),
      findsOneWidget,
    );
  });
}

Future<DiscordSocialSdkController> _controllerFor(
  DiscordSocialSdkAvailability availability,
) async {
  final controller = DiscordSocialSdkController(_SocialGateway(availability));
  await controller.initialize();
  return controller;
}

Future<void> _pumpAccountHome(
  WidgetTester tester,
  DiscordSocialSdkController controller,
) async {
  await tester.binding.setSurfaceSize(const Size(900, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: DiscordSocialSdkScope(
        controller: controller,
        child: Scaffold(
          body: OAuthAccountHomeView(
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
  await tester.pumpAndSettle();
}

final class _SocialGateway implements DiscordSocialSdkGateway {
  const _SocialGateway(this.availability);

  final DiscordSocialSdkAvailability availability;

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      availability;
}
