import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/chat_repository_factory.dart';
import 'package:flucord/src/domain/credential_vault.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_session.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  testWidgets('production bootstrap renders an honest disconnected state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FlucordApp(
        credentialVault: _EmptyCredentialVault(),
        chatRepositoryFactory: _UnusedRepositoryFactory(),
        discordOAuthAccountGateway: _OAuthGateway(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No chat transport connected'), findsOneWidget);
    expect(find.text('The Forge'), findsNothing);
    expect(
      find.byKey(const ValueKey('open-disconnected-connections')),
      findsOneWidget,
    );
  });

  testWidgets('explicit demo bootstrap retains deterministic workspace data', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FlucordApp.demo(discordOAuthAccountGateway: _OAuthGateway()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('The Forge'), findsOneWidget);
    expect(find.text('Demo workspace'), findsOneWidget);
    expect(find.text('No chat transport connected'), findsNothing);
  });

  testWidgets(
    'restored OAuth identity opens the native guild directory shell',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        FlucordApp(
          credentialVault: _EmptyCredentialVault(),
          chatRepositoryFactory: _UnusedRepositoryFactory(),
          discordOAuthAccountGateway: _OAuthGateway(
            restoredAccount: _oauthAccount(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(const ValueKey('oauth-guild-workspace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('oauth-guild-indicator-guild-1')),
        findsOneWidget,
      );
      expect(find.text('Messages unavailable for this server'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('oauth-guild-guild-2')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('oauth-guild-indicator-guild-2')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('oauth-account-home')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('oauth-account-home-view')),
        findsOneWidget,
      );
      expect(find.text('jack.fm'), findsWidgets);
      expect(find.text('Verified · MFA enabled · en-US'), findsOneWidget);
    },
  );

  testWidgets('app wiring replaces the OAuth placeholder with native friends', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FlucordApp(
        credentialVault: _EmptyCredentialVault(),
        chatRepositoryFactory: _UnusedRepositoryFactory(),
        discordOAuthAccountGateway: _OAuthGateway(
          restoredAccount: _oauthAccount(),
        ),
        discordSocialSdkGateway: _ReadySocialGateway(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('oauth-account-home')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('discord-friend-friend-1')),
      findsOneWidget,
    );
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('ONLINE — 1'), findsOneWidget);
    expect(find.text('Discord Social SDK is not bundled'), findsNothing);
  });

  testWidgets('link and unlink transition the disconnected native shell', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _OAuthGateway(authorizedAccount: _oauthAccount());

    await tester.pumpWidget(
      FlucordApp(
        credentialVault: _EmptyCredentialVault(),
        chatRepositoryFactory: _UnusedRepositoryFactory(),
        discordOAuthAccountGateway: gateway,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(
      find.byKey(const ValueKey('open-disconnected-connections')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('link-discord-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('oauth-guild-workspace')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('open-oauth-workspace-connections')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unlink-discord-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('No chat transport connected'), findsOneWidget);
    expect(find.byKey(const ValueKey('oauth-guild-workspace')), findsNothing);
    expect(gateway.clearCalls, 1);
  });
}

final class _EmptyCredentialVault implements CredentialVault {
  @override
  Future<void> clearDiscordSession() async {}

  @override
  Future<DiscordAccountSession?> readDiscordSession() async => null;

  @override
  Future<void> writeDiscordSession(DiscordAccountSession session) async {}
}

final class _UnusedRepositoryFactory implements ChatRepositoryFactory {
  @override
  Future<ChatRepository> create(DiscordAccountSession session) {
    throw StateError('No saved session should reach the repository factory.');
  }
}

final class _OAuthGateway implements DiscordOAuthAccountGateway {
  _OAuthGateway({this.restoredAccount, this.authorizedAccount});

  final DiscordOAuthAccount? restoredAccount;
  final DiscordOAuthAccount? authorizedAccount;
  int clearCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<DiscordOAuthAccount> authorize() {
    final account = authorizedAccount;
    if (account == null) {
      throw StateError('Authorization is not part of this test.');
    }
    return Future.value(account);
  }

  @override
  Future<void> clear() async => clearCalls++;

  @override
  Future<DiscordOAuthGuildMembership> fetchCurrentGuildMembership(
    String guildId,
  ) async => DiscordOAuthGuildMembership(
    guildId: guildId,
    nickname: 'Jack',
    joinedAt: DateTime.utc(2024, 1, 2),
  );

  @override
  void dispose() {}

  @override
  Future<bool> handleRedirect(Uri uri) async => false;

  @override
  Future<DiscordOAuthAccount?> restore() async => restoredAccount;
}

final class _ReadySocialGateway implements DiscordSocialSdkGateway {
  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      DiscordSocialSdkAvailability.ready;

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async => [
    DiscordRelationship(
      user: DiscordRelationshipUser(
        id: 'friend-1',
        displayName: 'Ada',
        status: DiscordPresenceStatus.online,
      ),
      kind: DiscordRelationshipKind.friend,
    ),
  ];
}

DiscordOAuthAccount _oauthAccount() => DiscordOAuthAccount(
  id: 'user-1',
  username: 'jack',
  displayName: 'Jack',
  accentColor: 0x5865F2,
  locale: 'en-US',
  isVerified: true,
  mfaEnabled: true,
  guilds: [
    DiscordOAuthGuild(
      id: 'guild-1',
      name: 'The Forge',
      isOwner: true,
      approximateMemberCount: 42,
      approximatePresenceCount: 7,
    ),
    DiscordOAuthGuild(id: 'guild-2', name: 'Night Shift', permissions: '8'),
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
