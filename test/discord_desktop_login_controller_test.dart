import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/application/discord_desktop_login_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/chat_repository_factory.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';
import 'package:flucord/src/domain/discord_session.dart';
import 'package:flucord/src/presentation/widgets/destructive_confirmation.dart';
import 'package:flucord/src/presentation/widgets/discord_desktop_login_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/contrast.dart';
import 'support/memory_credential_vault.dart';

void main() {
  test('connects and persists the session emitted by QR remote auth', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final vault = MemoryCredentialVault();
    final connection = ConnectionController(chat, vault, _RepositoryFactory());
    final gateway = _RemoteAuthGateway();
    final controller = DiscordDesktopLoginController(
      _RemoteAuthFactory(gateway),
      connection,
    );
    addTearDown(controller.dispose);
    addTearDown(connection.dispose);
    addTearDown(chat.dispose);

    await controller.start();
    gateway.add(const DiscordRemoteAuthQrReady('fingerprint'));
    await _settle();
    expect(controller.qrUri, Uri.parse('https://discord.com/ra/fingerprint'));

    gateway.add(
      const DiscordRemoteAuthUserPending(
        username: 'demo-user',
        discriminator: '0',
      ),
    );
    await _settle();
    expect(controller.pendingDisplayName, 'demo-user');

    const challenge = DiscordRemoteAuthCaptchaChallenge(
      siteKey: 'site-key',
      service: 'hcaptcha',
      userAgent: 'Discord test user agent',
      rqData: 'request-data',
      rqToken: 'request-token',
    );
    gateway.add(const DiscordRemoteAuthCaptchaRequired(challenge));
    await _settle();
    expect(controller.state, DiscordDesktopLoginState.captchaRequired);
    expect(controller.captchaChallenge, same(challenge));
    await controller.submitCaptcha('captcha-solution');
    expect(gateway.submittedCaptcha, 'captcha-solution');

    gateway.add(
      DiscordRemoteAuthCompleted(
        DiscordDesktopUserSession('desktop-authorization'),
      ),
    );
    await _waitFor(
      () => controller.state == DiscordDesktopLoginState.connected,
    );

    expect(connection.activeSession, isA<DiscordDesktopUserSession>());
    expect(vault.session, isA<DiscordDesktopUserSession>());
    expect(vault.session?.transportCredential, 'desktop-authorization');
  });

  test(
    'a sign-out with a locked cache forgets the account and says so',
    () async {
      final chat = ChatController(MockChatRepository(latency: Duration.zero));
      final vault = MemoryCredentialVault();
      final connection = ConnectionController(
        chat,
        vault,
        _RepositoryFactory(clearFails: true),
      );
      final controller = DiscordDesktopLoginController(
        _RemoteAuthFactory(_RemoteAuthGateway()),
        connection,
      );
      addTearDown(controller.dispose);
      addTearDown(connection.dispose);
      addTearDown(chat.dispose);
      await connection.connectSession(
        session: DiscordDesktopUserSession('desktop-authorization'),
        remember: true,
      );

      await controller.disconnect();

      expect(vault.session, isNull);
      expect(connection.mode, SessionMode.disconnected);
      expect(controller.errorMessage, contains('could not be removed'));
    },
  );

  for (final (name, theme) in [
    ('dark', FlucordTheme.dark),
    ('light', FlucordTheme.light),
  ]) {
    testWidgets('a failed sign-in reads at 4.5:1 in $name', (tester) async {
      final chat = ChatController(MockChatRepository(latency: Duration.zero));
      final connection = ConnectionController(
        chat,
        MemoryCredentialVault(),
        _RepositoryFactory(),
      );
      final gateway = _RemoteAuthGateway();
      final controller = DiscordDesktopLoginController(
        _RemoteAuthFactory(gateway),
        connection,
      );
      addTearDown(controller.dispose);
      addTearDown(connection.dispose);
      addTearDown(chat.dispose);

      await controller.start();
      gateway.add(const DiscordRemoteAuthFailed('The code expired.'));
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: DiscordDesktopLoginSection(
              controller: controller,
              connectionController: connection,
            ),
          ),
        ),
      );

      final error = tester.widget<Text>(
        find.textContaining('The code expired.'),
      );
      expectReadable(theme, error.style?.color, 4.5);
    });
  }

  testWidgets('renders a standard square QR code with a quiet zone', (
    tester,
  ) async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final connection = ConnectionController(
      chat,
      MemoryCredentialVault(),
      _RepositoryFactory(),
    );
    final gateway = _RemoteAuthGateway();
    final controller = DiscordDesktopLoginController(
      _RemoteAuthFactory(gateway),
      connection,
    );
    addTearDown(controller.dispose);
    addTearDown(connection.dispose);
    addTearDown(chat.dispose);

    await controller.start();
    gateway.add(const DiscordRemoteAuthQrReady('fingerprint'));
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: DiscordDesktopLoginSection(
            controller: controller,
            connectionController: connection,
          ),
        ),
      ),
    );

    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.eyeStyle.eyeShape, QrEyeShape.square);
    expect(qr.dataModuleStyle.dataModuleShape, QrDataModuleShape.square);
    expect(qr.padding, const EdgeInsets.all(16));
    expect(qr.gapless, isTrue);
    expect(qr.semanticsLabel, 'Discord sign-in QR code');
  });

  testWidgets('signing out asks first and keeps the session on cancel', (
    tester,
  ) async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final vault = MemoryCredentialVault();
    final connection = ConnectionController(chat, vault, _RepositoryFactory());
    final gateway = _RemoteAuthGateway();
    final controller = DiscordDesktopLoginController(
      _RemoteAuthFactory(gateway),
      connection,
    );
    addTearDown(controller.dispose);
    addTearDown(connection.dispose);
    addTearDown(chat.dispose);

    await controller.start();
    gateway.add(
      DiscordRemoteAuthCompleted(
        DiscordDesktopUserSession('desktop-authorization'),
      ),
    );
    await _pumpUntil(
      tester,
      () => controller.state == DiscordDesktopLoginState.connected,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: DiscordDesktopLoginSection(
            controller: controller,
            connectionController: connection,
          ),
        ),
      ),
    );
    final signOut = find.widgetWithText(FilledButton, 'Sign out');

    await tester.tap(signOut);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(vault.session, isNotNull);

    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(vault.session, isNotNull);
    await tester.tap(find.byKey(destructiveConfirmKey));
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () => vault.session == null);
  });
}

/// Waits on work that mixes real time and the test clock: the sign-in writes
/// through futures on both.
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 50 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(_settle);
  }
  expect(condition(), isTrue);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

final class _RemoteAuthFactory implements DiscordRemoteAuthGatewayFactory {
  const _RemoteAuthFactory(this.gateway);

  final DiscordRemoteAuthGateway gateway;

  @override
  DiscordRemoteAuthGateway create() => gateway;
}

final class _RemoteAuthGateway implements DiscordRemoteAuthGateway {
  final StreamController<DiscordRemoteAuthEvent> _events =
      StreamController.broadcast();
  String? submittedCaptcha;

  @override
  Stream<DiscordRemoteAuthEvent> get events => _events.stream;

  void add(DiscordRemoteAuthEvent event) => _events.add(event);

  @override
  Future<void> start() async {}

  @override
  Future<void> submitCaptcha(String response) async {
    submittedCaptcha = response;
  }

  @override
  Future<void> close() async {
    if (!_events.isClosed) await _events.close();
  }
}

final class _RepositoryFactory implements ChatRepositoryFactory {
  _RepositoryFactory({this.clearFails = false});

  final bool clearFails;

  @override
  Future<ChatRepository> create(DiscordAccountSession session) async =>
      MockChatRepository(latency: Duration.zero);

  @override
  Future<void> clearCache() async {
    if (clearFails) throw StateError('The file is locked');
  }
}
