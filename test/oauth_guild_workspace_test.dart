import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/oauth_guild_directory_controller.dart';
import 'package:flucord/src/application/oauth_guild_membership_controller.dart';
import 'package:flucord/src/application/discord_social_sdk_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';
import 'package:flucord/src/presentation/widgets/discord_social_sdk_scope.dart';
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
      discriminator: '0042',
      accentColor: 0x5865F2,
      locale: 'en-US',
      isVerified: true,
      mfaEnabled: true,
      publicFlags: 64,
      guilds: [
        DiscordOAuthGuild(id: 'guild-1', name: 'The Forge'),
        DiscordOAuthGuild(id: 'guild-2', name: 'Night Shift'),
      ],
      connections: [
        DiscordOAuthConnection(
          id: 'spotify-1',
          name: 'jack.fm',
          type: 'spotify',
          verified: true,
          visibility: 1,
        ),
      ],
    );
    final controller = OAuthGuildDirectoryController()..reconcile(account);
    final membershipController = OAuthGuildMembershipController(_OAuthGateway())
      ..reconcileAccount(account.id);
    addTearDown(membershipController.dispose);
    final socialController = DiscordSocialSdkController(_SocialGateway());
    await socialController.initialize();
    addTearDown(socialController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: DiscordSocialSdkScope(
          controller: socialController,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => OAuthGuildWorkspace(
              account: account,
              accountHomeSelected: controller.accountHomeSelected,
              membershipController: membershipController,
              selectedGuildId: controller.selectedGuildId,
              onOpenAccountHome: controller.selectAccountHome,
              onSelectGuild: (guildId) =>
                  controller.selectGuild(account, guildId),
              onOpenConnections: () {},
              onToggleTheme: () {},
              isDark: true,
            ),
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
    await tester.tap(find.byKey(const ValueKey('oauth-account-home')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('oauth-account-home-view')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('oauth-account-sidebar')), findsNothing);
    expect(
      find.byKey(const ValueKey('oauth-account-profile-banner')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('loads the selected server profile in the wide sidebar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = DiscordOAuthAccount(
      id: 'user-1',
      username: 'jack',
      displayName: 'Jack',
      discriminator: '0042',
      accentColor: 0x5865F2,
      locale: 'en-US',
      isVerified: true,
      mfaEnabled: true,
      publicFlags: 64,
      guilds: [
        DiscordOAuthGuild(id: 'guild-1', name: 'The Forge'),
        DiscordOAuthGuild(id: 'guild-2', name: 'Night Shift'),
      ],
      connections: [
        DiscordOAuthConnection(
          id: 'spotify-1',
          name: 'jack.fm',
          type: 'spotify',
          verified: true,
          visibility: 1,
        ),
      ],
    );
    final directoryController = OAuthGuildDirectoryController()
      ..reconcile(account);
    final gateway = _OAuthGateway();
    final membershipController = OAuthGuildMembershipController(gateway)
      ..reconcileAccount(account.id);
    addTearDown(membershipController.dispose);
    final socialController = DiscordSocialSdkController(_SocialGateway());
    await socialController.initialize();
    addTearDown(socialController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: DiscordSocialSdkScope(
          controller: socialController,
          child: ListenableBuilder(
            listenable: directoryController,
            builder: (context, _) => OAuthGuildWorkspace(
              account: account,
              accountHomeSelected: directoryController.accountHomeSelected,
              membershipController: membershipController,
              selectedGuildId: directoryController.selectedGuildId,
              onOpenAccountHome: directoryController.selectAccountHome,
              onSelectGuild: (guildId) =>
                  directoryController.selectGuild(account, guildId),
              onOpenConnections: () {},
              onToggleTheme: () {},
              isDark: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profile guild-1'), findsOneWidget);
    expect(find.text('2 roles'), findsOneWidget);
    expect(gateway.guildIds, const ['guild-1']);

    await tester.tap(find.byKey(const ValueKey('oauth-account-home')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('oauth-account-home-view')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('oauth-account-home-indicator')),
      findsOneWidget,
    );
    expect(find.text('jack.fm'), findsWidgets);
    expect(find.text('jack#0042'), findsWidgets);
    expect(
      find.text('Verified · MFA enabled · en-US · Badges 0x40'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('oauth-account-profile-banner')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('oauth-guild-guild-2')));
    await tester.pumpAndSettle();

    expect(find.text('Profile guild-2'), findsOneWidget);
    expect(gateway.guildIds, const ['guild-1', 'guild-2']);
    expect(tester.takeException(), isNull);
  });
}

final class _SocialGateway implements DiscordSocialSdkGateway {
  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      DiscordSocialSdkAvailability.sdkNotBundled;

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async => const [];

  @override
  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  }) async {}
}

final class _OAuthGateway implements DiscordOAuthAccountGateway {
  final List<String> guildIds = [];

  @override
  bool get isConfigured => true;

  @override
  Future<DiscordOAuthAccount> authorize() =>
      throw StateError('Authorization is not part of this test.');

  @override
  Future<void> clear() async {}

  @override
  void dispose() {}

  @override
  Future<DiscordOAuthGuildMembership> fetchCurrentGuildMembership(
    String guildId,
  ) async {
    guildIds.add(guildId);
    return DiscordOAuthGuildMembership(
      guildId: guildId,
      nickname: 'Profile $guildId',
      roleIds: const ['role-1', 'role-2'],
      joinedAt: DateTime.utc(2024, 1, 2),
    );
  }

  @override
  Future<bool> handleRedirect(Uri uri) async => false;

  @override
  Future<DiscordOAuthAccount?> restore() async => null;
}
