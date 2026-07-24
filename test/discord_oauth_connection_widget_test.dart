import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/workspace_controller.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';
import 'package:flucord/src/platform/desktop_integration.dart';

void main() {
  testWidgets('links and unlinks an OAuth account without changing chat mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _OAuthGateway();

    await tester.pumpWidget(
      FlucordApp.demo(discordOAuthAccountGateway: gateway),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await tester.pumpAndSettle();

    expect(find.text('Discord account'), findsOneWidget);
    expect(find.text('No Discord account connected.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('link-discord-account')));
    await tester.pumpAndSettle();

    expect(find.text('Jack · 2 servers'), findsOneWidget);
    expect(find.byKey(const ValueKey('developer-bot-transport')), findsNothing);
    expect(find.text('AUTHORIZED SERVERS · 2'), findsOneWidget);
    expect(find.text('CONNECTED ACCOUNTS · 2'), findsOneWidget);
    expect(find.text('jack.fm'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('discord-oauth-connection-spotify-spotify-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('discord-oauth-guild-guild-1')),
      findsOneWidget,
    );
    expect(find.text('Owner · 42 members · 7 online'), findsOneWidget);
    expect(find.text('Administrator · 12 members · 3 online'), findsOneWidget);
    expect(gateway.authorizeCalls, 1);

    await tester.tap(find.byKey(const ValueKey('unlink-discord-account')));
    await tester.pumpAndSettle();

    expect(find.text('No Discord account connected.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('discord-oauth-guild-directory')),
      findsNothing,
    );
    expect(gateway.clearCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the normal account directory scrollable when compact', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FlucordApp.demo(
        discordOAuthAccountGateway: _OAuthGateway(extraGuildCount: 6),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('link-discord-account')), findsOneWidget);
    expect(find.byKey(const ValueKey('discord-bot-token')), findsNothing);
    expect(find.byKey(const ValueKey('developer-bot-transport')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('link-discord-account')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('discord-oauth-guild-directory')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('discord-oauth-guild-directory')),
      120,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('discord-oauth-guild-guild-8')),
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('discord-oauth-guild-directory')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.byKey(const ValueKey('discord-oauth-guild-guild-8')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('one account action connects and disconnects both grants', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final oauthGateway = _OAuthGateway();
    final socialGateway = _SocialGateway();

    await tester.pumpWidget(
      FlucordApp.demo(
        discordOAuthAccountGateway: oauthGateway,
        discordSocialSdkGateway: socialGateway,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('link-discord-account')));
    await tester.pumpAndSettle();

    expect(oauthGateway.authorizeCalls, 1);
    expect(socialGateway.authorizeCalls, 1);
    expect(
      find.text('Jack · 2 servers · Friends and DMs connected'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('unlink-discord-account')));
    await tester.pumpAndSettle();

    expect(oauthGateway.clearCalls, 1);
    expect(socialGateway.disconnectCalls, 1);
    expect(find.text('No Discord account connected.'), findsOneWidget);
  });

  testWidgets('reveals bot credentials only in an explicit developer build', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FlucordApp.demo(
        discordOAuthAccountGateway: _OAuthGateway(),
        enableBotTransport: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('developer-bot-transport')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('discord-bot-token')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('developer-bot-transport')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('discord-bot-token')), findsOneWidget);
    expect(find.text('Application bot token'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the authorized guild directory empty state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FlucordApp.demo(
        discordOAuthAccountGateway: _OAuthGateway(emptyGuilds: true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-connections')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link-discord-account')));
    await tester.pumpAndSettle();

    expect(find.text('AUTHORIZED SERVERS · 0'), findsOneWidget);
    expect(
      find.text('No servers were returned by the guilds scope.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('forwards desktop protocol callbacks to OAuth', (tester) async {
    final gateway = _OAuthGateway();
    final desktop = _DesktopIntegration();

    await tester.pumpWidget(
      FlucordApp.demo(
        discordOAuthAccountGateway: gateway,
        desktopIntegration: desktop,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    desktop.emit(Uri.parse('flucord://oauth/discord/callback?code=x'));
    await tester.pump();

    expect(
      gateway.handledUri,
      Uri.parse('flucord://oauth/discord/callback?code=x'),
    );
  });
}

final class _OAuthGateway implements DiscordOAuthAccountGateway {
  _OAuthGateway({this.extraGuildCount = 0, this.emptyGuilds = false});

  final int extraGuildCount;
  final bool emptyGuilds;
  int authorizeCalls = 0;
  int clearCalls = 0;
  Uri? handledUri;

  @override
  bool get isConfigured => true;

  @override
  Future<DiscordOAuthAccount> authorize() async {
    authorizeCalls++;
    return DiscordOAuthAccount(
      id: '123456789012345678',
      username: 'jack',
      displayName: 'Jack',
      guilds: emptyGuilds
          ? const []
          : [
              DiscordOAuthGuild(
                id: 'guild-1',
                name: 'The Forge',
                isOwner: true,
                permissions: '8',
                approximateMemberCount: 42,
                approximatePresenceCount: 7,
              ),
              DiscordOAuthGuild(
                id: 'guild-2',
                name: 'Night Shift',
                permissions: '8',
                approximateMemberCount: 12,
                approximatePresenceCount: 3,
              ),
              for (var index = 0; index < extraGuildCount; index++)
                DiscordOAuthGuild(
                  id: 'guild-${index + 3}',
                  name: 'Server ${index + 3}',
                ),
            ],
      connections: [
        DiscordOAuthConnection(
          id: 'spotify-1',
          name: 'jack.fm',
          type: 'spotify',
          verified: true,
          showActivity: true,
          visibility: 1,
        ),
        DiscordOAuthConnection(
          id: 'github-1',
          name: 'redstone-md',
          type: 'github',
        ),
      ],
    );
  }

  @override
  Future<void> clear() async => clearCalls++;

  @override
  Future<DiscordOAuthGuildMembership> fetchCurrentGuildMembership(
    String guildId,
  ) => throw StateError('Guild membership is not part of this test.');

  @override
  void dispose() {}

  @override
  Future<bool> handleRedirect(Uri uri) async {
    handledUri = uri;
    return true;
  }

  @override
  Future<DiscordOAuthAccount?> restore() async => null;
}

final class _DesktopIntegration implements DesktopIntegration {
  void Function(Uri uri)? _onProtocolUri;

  @override
  void attach({
    required ChatController chatController,
    required WorkspaceController workspaceController,
    required void Function(Uri uri) onProtocolUri,
  }) {
    _onProtocolUri = onProtocolUri;
  }

  void emit(Uri uri) => _onProtocolUri!(uri);

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}
}

final class _SocialGateway implements DiscordSocialSdkGateway {
  int authorizeCalls = 0;
  int disconnectCalls = 0;

  @override
  Future<DiscordSocialSdkAuthentication> authorize() async {
    authorizeCalls++;
    return DiscordSocialSdkAuthentication.readyFor('123456789012345678');
  }

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      DiscordSocialSdkAvailability.ready;

  @override
  Future<void> disconnect() async => disconnectCalls++;

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async => const [];

  @override
  Future<DiscordSocialSdkAuthentication> restoreAuthentication() async =>
      DiscordSocialSdkAuthentication.signedOut;

  @override
  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  }) async {}
}
