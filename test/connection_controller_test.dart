import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/chat_controller.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/data/discord/discord_api_client.dart';
import 'package:flucord/src/data/discord/discord_repository_factory.dart';
import 'package:flucord/src/data/mock_chat_repository.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/credential_vault.dart';

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
      expect(controller.mode, SessionMode.discordBot);
      expect(controller.state, ConnectionActionState.connected);
      expect(vault.token, 'bot-token');

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
    expect(controller.mode, SessionMode.discordBot);
    expect(controller.state, ConnectionActionState.connected);
    expect(controller.hasSavedCredential, isFalse);
    expect(controller.errorMessage, contains('Credential Manager'));
  });
}

final class _MemoryCredentialVault implements CredentialVault {
  String? token;

  @override
  Future<void> clearDiscordBotToken() async => token = null;

  @override
  Future<String?> readDiscordBotToken() async => token;

  @override
  Future<void> writeDiscordBotToken(String token) async {
    this.token = token;
  }
}

final class _FailingCredentialVault implements CredentialVault {
  @override
  Future<void> clearDiscordBotToken() async => throw StateError('vault');

  @override
  Future<String?> readDiscordBotToken() async => null;

  @override
  Future<void> writeDiscordBotToken(String token) async =>
      throw StateError('vault');
}

final class _StaticRepositoryFactory implements ChatRepositoryFactory {
  _StaticRepositoryFactory(this.repository);

  final ChatRepository repository;

  @override
  Future<ChatRepository> createDiscordRepository(String botToken) async =>
      repository;
}

final class _RejectingRepositoryFactory implements ChatRepositoryFactory {
  @override
  Future<ChatRepository> createDiscordRepository(String botToken) {
    throw const DiscordApiException(statusCode: 401, message: 'Unauthorized');
  }
}

final class _CountingRepositoryFactory implements ChatRepositoryFactory {
  int calls = 0;

  @override
  Future<ChatRepository> createDiscordRepository(String botToken) async {
    calls++;
    return MockChatRepository(latency: Duration.zero);
  }
}
