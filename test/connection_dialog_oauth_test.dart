import 'dart:async';

import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/application/discord_account_connection_controller.dart';
import 'package:flucord/src/application/discord_desktop_login_controller.dart';
import 'package:flucord/src/application/discord_oauth_controller.dart';
import 'package:flucord/src/application/discord_social_sdk_controller.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/chat_repository_factory.dart';
import 'package:flucord/src/domain/credential_vault.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_remote_auth.dart';
import 'package:flucord/src/domain/discord_session.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';
import 'package:flucord/src/presentation/widgets/connection_dialog.dart';
import 'package:flucord/src/presentation/widgets/discord_account_connection_scope.dart';
import 'package:flucord/src/presentation/widgets/oauth_connection_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the connection dialog offers the OAuth identity', (
    tester,
  ) async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final connection = ConnectionController(
      chat,
      _MemoryVault(),
      _RepositoryFactory(),
    );
    final login = DiscordDesktopLoginController(
      const _RemoteAuthFactory(),
      connection,
    );
    final oauth = DiscordOAuthController(_OAuthGateway());
    final social = DiscordSocialSdkController(_SocialGateway());
    final account = DiscordAccountConnectionController(oauth, social);
    addTearDown(chat.dispose);
    addTearDown(connection.dispose);
    addTearDown(login.dispose);
    addTearDown(oauth.dispose);
    addTearDown(social.dispose);
    addTearDown(account.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: DiscordAccountConnectionScope(
          controller: account,
          child: ConnectionDialog(
            controller: connection,
            desktopLoginController: login,
          ),
        ),
      ),
    );
    await tester.pump();

    // The section was written and never placed; this is what keeps it placed.
    expect(find.byType(OAuthConnectionSection), findsOne);
    expect(find.text('Discord account'), findsOne);
  });

  testWidgets('a host with no account scope shows only the session login', (
    tester,
  ) async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final connection = ConnectionController(
      chat,
      _MemoryVault(),
      _RepositoryFactory(),
    );
    final login = DiscordDesktopLoginController(
      const _RemoteAuthFactory(),
      connection,
    );
    addTearDown(chat.dispose);
    addTearDown(connection.dispose);
    addTearDown(login.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: ConnectionDialog(
          controller: connection,
          desktopLoginController: login,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(OAuthConnectionSection), findsNothing);
  });
}

final class _MemoryVault implements CredentialVault {
  DiscordAccountSession? _session;

  @override
  Future<void> clearDiscordSession() async => _session = null;

  @override
  Future<DiscordAccountSession?> readDiscordSession() async => _session;

  @override
  Future<void> writeDiscordSession(DiscordAccountSession session) async =>
      _session = session;
}

final class _RepositoryFactory implements ChatRepositoryFactory {
  @override
  Future<ChatRepository> create(DiscordAccountSession session) async =>
      MockChatRepository(latency: Duration.zero);
}

final class _RemoteAuthFactory implements DiscordRemoteAuthGatewayFactory {
  const _RemoteAuthFactory();

  @override
  DiscordRemoteAuthGateway create() => _RemoteAuthGateway();
}

final class _RemoteAuthGateway implements DiscordRemoteAuthGateway {
  final StreamController<DiscordRemoteAuthEvent> _events =
      StreamController.broadcast();

  @override
  Stream<DiscordRemoteAuthEvent> get events => _events.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> submitCaptcha(String response) async {}

  @override
  Future<void> close() async {
    if (!_events.isClosed) await _events.close();
  }
}

final class _OAuthGateway implements DiscordOAuthAccountGateway {
  @override
  bool get isConfigured => true;

  @override
  Future<DiscordOAuthAccount> authorize() async =>
      throw const DiscordOAuthException('Not part of this test.');

  @override
  Future<void> clear() async {}

  @override
  Future<DiscordOAuthGuildMembership> fetchCurrentGuildMembership(
    String guildId,
  ) => throw StateError('Membership is not part of this test.');

  @override
  Future<bool> handleRedirect(Uri uri) async => false;

  @override
  Future<DiscordOAuthAccount?> restore() async => null;

  @override
  void dispose() {}
}

final class _SocialGateway implements DiscordSocialSdkGateway {
  @override
  Future<DiscordSocialSdkAuthentication> authorize() async =>
      throw const DiscordSocialSdkException('authorization_failed');

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      DiscordSocialSdkAvailability.ready;

  @override
  Future<void> disconnect() async {}

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
