import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/application/discord_desktop_login_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/chat_repository_factory.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';
import 'package:flucord/src/domain/discord_session.dart';
import 'package:flucord/src/presentation/widgets/connection_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_credential_vault.dart';
import 'support/session_harness.dart' show FakeRemoteAuth;

void main() {
  /// Opens the Connections dialog over a page, as the shell does, and starts a
  /// QR sign-in in it. Answers with the sign-in, so a test can finish it.
  Future<(FakeRemoteAuth, DiscordDesktopLoginController)> startSignInInDialog(
    WidgetTester tester,
  ) async {
    final remoteAuth = FakeRemoteAuth();
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final connection = ConnectionController(
      chat,
      MemoryCredentialVault(),
      _RepositoryFactory(),
    );
    final login = DiscordDesktopLoginController(remoteAuth, connection);
    addTearDown(chat.dispose);
    addTearDown(connection.dispose);
    addTearDown(login.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ConnectionDialog(
                controller: connection,
                desktopLoginController: login,
              ),
            ),
            child: const Text('Open connections'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open connections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in with QR code'));
    await tester.pump();
    return (remoteAuth, login);
  }

  testWidgets('a QR sign-in that succeeds closes the dialog', (tester) async {
    final (remoteAuth, login) = await startSignInInDialog(tester);

    remoteAuth.add(
      DiscordRemoteAuthCompleted(DiscordDesktopUserSession('token')),
    );
    // Connecting opens the account's workspace, which needs the real event
    // loop as well as frames.
    for (var attempt = 0; attempt < 50 && login.isBusy; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pumpAndSettle();

    expect(find.byType(ConnectionDialog), findsNothing);
  });

  testWidgets('a QR sign-in that fails keeps the dialog open with the error', (
    tester,
  ) async {
    final (remoteAuth, _) = await startSignInInDialog(tester);

    remoteAuth.add(const DiscordRemoteAuthFailed('The QR code expired.'));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectionDialog), findsOneWidget);
    expect(find.text('The QR code expired.'), findsOneWidget);
  });
}

final class _RepositoryFactory implements ChatRepositoryFactory {
  @override
  Future<ChatRepository> create(DiscordAccountSession session) async =>
      MockChatRepository(latency: Duration.zero);

  @override
  Future<void> clearCache() async {}
}
