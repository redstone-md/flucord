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
        botTransportEnabled: true,
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

  test('rejects an unauthorized token and disconnects cleanly', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final controller = ConnectionController(
      chat,
      _MemoryCredentialVault(),
      _RejectingRepositoryFactory(),
      botTransportEnabled: true,
    );
    addTearDown(chat.dispose);
    await chat.load();

    final connected = await controller.connectWithBotToken(
      token: 'rejected-token',
      remember: true,
    );

    expect(connected, isFalse);
    expect(controller.mode, SessionMode.disconnected);
    expect(controller.errorMessage, 'Discord rejected this bot token.');
    expect(chat.state, ChatLoadState.ready);
    expect(chat.workspace?.spaces, isEmpty);
  });

  test('does not create a repository for empty input', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final factory = _CountingRepositoryFactory();
    final controller = ConnectionController(
      chat,
      _MemoryCredentialVault(),
      factory,
      botTransportEnabled: true,
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
      botTransportEnabled: true,
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

  test('automatically restores a typed session from the vault', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final vault = _MemoryCredentialVault()
      ..session = DiscordBotSession('saved-token');
    final factory = _StaticRepositoryFactory(
      MockChatRepository(latency: Duration.zero),
    );
    final controller = ConnectionController(
      chat,
      vault,
      factory,
      botTransportEnabled: true,
    );
    addTearDown(chat.dispose);

    await controller.initialize();

    expect(controller.hasSavedCredential, isTrue);
    expect(controller.mode, SessionMode.discord);
    expect(controller.state, ConnectionActionState.connected);
    expect(factory.receivedSession, isA<DiscordBotSession>());
    expect(factory.receivedSession?.transportCredential, 'saved-token');
    expect(vault.writeCalls, 0);
  });

  test(
    'opens an empty disconnected workspace without a saved session',
    () async {
      final chat = ChatController(MockChatRepository(latency: Duration.zero));
      final controller = ConnectionController(
        chat,
        _MemoryCredentialVault(),
        _CountingRepositoryFactory(),
      );
      addTearDown(chat.dispose);

      await controller.initialize();

      expect(controller.mode, SessionMode.disconnected);
      expect(controller.state, ConnectionActionState.idle);
      expect(chat.state, ChatLoadState.ready);
      expect(chat.workspace?.spaces, isEmpty);
    },
  );

  test('a rejected saved session never reveals demo servers', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final vault = _MemoryCredentialVault()
      ..session = DiscordBotSession('rejected-token');
    final controller = ConnectionController(
      chat,
      vault,
      _RejectingRepositoryFactory(),
      botTransportEnabled: true,
    );
    addTearDown(chat.dispose);

    await controller.initialize();

    expect(controller.mode, SessionMode.disconnected);
    expect(controller.state, ConnectionActionState.failure);
    expect(controller.hasSavedCredential, isTrue);
    expect(chat.workspace?.spaces, isEmpty);
    expect(
      chat.workspace?.spaces.any((space) => space.name == 'The Forge'),
      isFalse,
    );
  });

  test(
    'explicit demo initialization does not restore a saved session',
    () async {
      final chat = ChatController(MockChatRepository(latency: Duration.zero));
      final vault = _MemoryCredentialVault()
        ..session = DiscordBotSession('saved-token');
      final factory = _CountingRepositoryFactory();
      final controller = ConnectionController(
        chat,
        vault,
        factory,
        initialMode: SessionMode.demo,
      );
      addTearDown(chat.dispose);

      await controller.initialize(restoreSavedSession: false);

      expect(controller.mode, SessionMode.demo);
      expect(chat.workspace?.spaces.first.name, 'The Forge');
      expect(factory.calls, 0);
    },
  );

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
    expect(controller.mode, SessionMode.disconnected);
    expect(controller.activeSession, isNull);
    expect(
      controller.errorMessage,
      'This authorized Discord session does not expose full chat and Gateway access.',
    );
  });

  test(
    'keeps saved bot credentials dormant in a normal client build',
    () async {
      final chat = ChatController(MockChatRepository(latency: Duration.zero));
      final vault = _MemoryCredentialVault()
        ..session = DiscordBotSession('saved-token');
      final factory = _CountingRepositoryFactory();
      final controller = ConnectionController(chat, vault, factory);
      addTearDown(chat.dispose);

      await controller.initialize();

      expect(controller.mode, SessionMode.disconnected);
      expect(controller.hasSavedCredential, isFalse);
      expect(vault.readCalls, 0);
      expect(vault.token, 'saved-token');
      expect(factory.calls, 0);

      expect(await controller.connectSavedCredential(), isFalse);
      expect(vault.readCalls, 0);
      expect(factory.calls, 0);
    },
  );

  test('rejects bot sessions at the normal client boundary', () async {
    final chat = ChatController(MockChatRepository(latency: Duration.zero));
    final factory = _CountingRepositoryFactory();
    final controller = ConnectionController(
      chat,
      _MemoryCredentialVault(),
      factory,
    );
    addTearDown(chat.dispose);

    expect(
      await controller.connectSession(
        session: DiscordBotSession('bot-token'),
        remember: false,
      ),
      isFalse,
    );
    expect(
      controller.errorMessage,
      'Developer bot transport is disabled in this build.',
    );
    expect(factory.calls, 0);
  });
}

final class _MemoryCredentialVault implements CredentialVault {
  DiscordAccountSession? session;
  int readCalls = 0;
  int writeCalls = 0;

  String? get token => session?.transportCredential;

  @override
  Future<void> clearDiscordSession() async => session = null;

  @override
  Future<DiscordAccountSession?> readDiscordSession() async {
    readCalls++;
    return session;
  }

  @override
  Future<void> writeDiscordSession(DiscordAccountSession session) async {
    writeCalls++;
    this.session = session;
  }
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
