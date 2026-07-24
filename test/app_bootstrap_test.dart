import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/chat_repository_factory.dart';
import 'package:flucord/src/domain/credential_vault.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_session.dart';

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
        discordOAuthAccountGateway: _EmptyOAuthGateway(),
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
      FlucordApp.demo(discordOAuthAccountGateway: _EmptyOAuthGateway()),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('The Forge'), findsOneWidget);
    expect(find.text('Demo workspace'), findsOneWidget);
    expect(find.text('No chat transport connected'), findsNothing);
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

final class _EmptyOAuthGateway implements DiscordOAuthAccountGateway {
  @override
  bool get isConfigured => true;

  @override
  Future<DiscordOAuthAccount> authorize() {
    throw StateError('Authorization is not part of this test.');
  }

  @override
  Future<void> clear() async {}

  @override
  void dispose() {}

  @override
  Future<bool> handleRedirect(Uri uri) async => false;

  @override
  Future<DiscordOAuthAccount?> restore() async => null;
}
