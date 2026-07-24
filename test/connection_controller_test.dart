import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_repository_factory.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/credential_vault.dart';
import 'package:flucord/src/domain/discord_session.dart';

void main() {
  test(
    'connects through factory and stores only remembered credentials',
    () async {
      final chat = ChatController(MockChatRepository(latency: Duration.zero));
      final vault = _MemoryCredentialVault();
      final controller = ConnectionController(
        chat,
        vault,
        _StaticRepositoryFactory(MockChatRepository(latency: Duration.zero)),
      );
      addTearDown(chat.dispose);
      await chat.load();

      final connected = await controller.connectWithBotToken(
        token: ' bot-token ',
        remember: true,
      );

      expect(connected, isTrue);
      expect(controller.mode, SessionMode.discord);
      expect(controller.state, ConnectionActionState.connected);
      expect(vault.token, 'bot-token');
      expect(controller.activeSession, isA<DiscordBotSession>());
      expect(
        controller.capabilities,
        contains(DiscordSessionCapability.realtimeGateway),
      );

      await controller.connectWithBotToken(
        token: 'ephemeral-token',
        remember: false,
      );
      expect(vault.token, isNull);
    },
  );

  test('rejects an unauthorized token and restores local workspace', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final controller = ConnectionController(
      chat,
      _MemoryCredentialVault(),
      _RejectingRepositoryFactory(),
    );
    addTearDown(chat.dispose);
    await chat.load();

    final connected = await controller.connectWithBotToken(
      token: 'rejected-token',
      remember: true,
    );

    expect(connected, isFalse);
    expect(controller.mode, SessionMode.local);
    expect(controller.errorMessage, 'Discord rejected this bot token.');
    expect(chat.state, ChatLoadState.ready);
    expect(chat.workspace?.spaces.first.name, 'The Forge');
  });

  test('does not create a repository for empty input', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final factory = _CountingRepositoryFactory();
    final controller = ConnectionController(
      chat,
      _MemoryCredentialVault(),
      factory,
    );
    addTearDown(chat.dispose);

    expect(
      await controller.connectWithBotToken(token: '  ', remember: false),
      isFalse,
    );
    expect(factory.calls, 0);
  });

  test('keeps a live session when credential persistence fails', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final controller = ConnectionController(
      chat,
      _FailingCredentialVault(),
      _StaticRepositoryFactory(MockChatRepository(latency: Duration.zero)),
    );
    addTearDown(chat.dispose);
    await chat.load();

    final connected = await controller.connectWithBotToken(
      token: 'bot-token',
      remember: true,
    );

    expect(connected, isTrue);
    expect(controller.mode, SessionMode.discord);
    expect(controller.state, ConnectionActionState.connected);
    expect(controller.hasSavedCredential, isFalse);
    expect(controller.errorMessage, contains('credential vault'));
  });

  test('restores a typed session from the credential vault', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final vault = _MemoryCredentialVault()
      ..session = DiscordBotSession('saved-token');
    final factory = _StaticRepositoryFactory(
      MockChatRepository(latency: Duration.zero),
    );
    final controller = ConnectionController(chat, vault, factory);
    addTearDown(chat.dispose);
    await chat.load();

    await controller.initialize();
    final connected = await controller.connectSavedCredential();

    expect(controller.hasSavedCredential, isTrue);
    expect(connected, isTrue);
    expect(factory.receivedSession, isA<DiscordBotSession>());
    expect(factory.receivedSession?.transportCredential, 'saved-token');
  });

  test('rejects a scoped OAuth session at the full-chat boundary', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final controller = ConnectionController(
      chat,
      _MemoryCredentialVault(),
      _UnsupportedRepositoryFactory(),
    );
    addTearDown(chat.dispose);
    await chat.load();

    final connected = await controller.connectSession(
      session: DiscordOAuthUserSession(
        accessToken: 'oauth-token',
        scopes: const ['identify', 'guilds'],
        expiresAt: DateTime.utc(2026, 8),
      ),
      remember: false,
    );

    expect(connected, isFalse);
    expect(controller.mode, SessionMode.local);
    expect(controller.activeSession, isNull);
    expect(
      controller.errorMessage,
      'This authorized Discord session does not expose full chat and Gateway access.',
    );
  });
}

final class _MemoryCredentialVault implements CredentialVault {
  DiscordAccountSession? session;

  String? get token => session?.transportCredential;

  @override
  Future<void> clearDiscordSession() async => session = null;

  @override
  Future<DiscordAccountSession?> readDiscordSession() async => session;

  @override
  Future<void> writeDiscordSession(DiscordAccountSession session) async =>
      this.session = session;
}

final class _FailingCredentialVault implements CredentialVault {
  @override
  Future<void> clearDiscordSession() async => throw StateError('vault');

  @override
  Future<DiscordAccountSession?> readDiscordSession() async => null;

  @override
  Future<void> writeDiscordSession(DiscordAccountSession session) async =>
      throw StateError('vault');
}

final class _StaticRepositoryFactory implements ChatRepositoryFactory {
  _StaticRepositoryFactory(this.repository);

  final ChatRepository repository;
  DiscordAccountSession? receivedSession;

  @override
  Future<ChatRepository> create(DiscordAccountSession session) async {
    receivedSession = session;
    return repository;
  }
}

final class _RejectingRepositoryFactory implements ChatRepositoryFactory {
  @override
  Future<ChatRepository> create(DiscordAccountSession session) {
    throw const DiscordApiException(statusCode: 401, message: 'Unauthorized');
  }
}

final class _UnsupportedRepositoryFactory implements ChatRepositoryFactory {
  @override
  Future<ChatRepository> create(DiscordAccountSession session) {
    throw UnsupportedDiscordSessionException(session.kind);
  }
}

final class _CountingRepositoryFactory implements ChatRepositoryFactory {
  int calls = 0;

  @override
  Future<ChatRepository> create(DiscordAccountSession session) async {
    calls++;
    return MockChatRepository(latency: Duration.zero);
  }
}
