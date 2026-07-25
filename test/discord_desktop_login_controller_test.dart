import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/application/discord_desktop_login_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/chat_repository_factory.dart';
import 'package:flucord/src/domain/credential_vault.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';
import 'package:flucord/src/domain/discord_session.dart';
import 'package:flucord/src/presentation/widgets/discord_desktop_login_section.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  test('connects and persists the session emitted by QR remote auth', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final vault = _MemoryVault();
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
      const DiscordRemoteAuthUserPending(username: 'demo-user', discriminator: '0'),
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

  testWidgets('renders a standard square QR code with a quiet zone', (
    tester,
  ) async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final connection = ConnectionController(
      chat,
      _MemoryVault(),
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

final class _MemoryVault implements CredentialVault {
  DiscordAccountSession? session;

  @override
  Future<void> clearDiscordSession() async => session = null;

  @override
  Future<DiscordAccountSession?> readDiscordSession() async => session;

  @override
  Future<void> writeDiscordSession(DiscordAccountSession session) async {
    this.session = session;
  }
}

final class _RepositoryFactory implements ChatRepositoryFactory {
  @override
  Future<ChatRepository> create(DiscordAccountSession session) async =>
      MockChatRepository(latency: Duration.zero);
}
