import 'package:flutter/foundation.dart';

import '../data/discord/discord_api_client.dart';
import '../data/discord/discord_repository_factory.dart';
import '../data/mock_chat_repository.dart';
import '../domain/credential_vault.dart';
import 'chat_controller.dart';

enum SessionMode { local, discordBot }

enum ConnectionActionState { idle, connecting, connected, failure }

final class ConnectionController extends ChangeNotifier {
  ConnectionController(
    this._chatController,
    this._credentialVault,
    this._repositoryFactory,
  );

  final ChatController _chatController;
  final CredentialVault _credentialVault;
  final ChatRepositoryFactory _repositoryFactory;

  SessionMode _mode = SessionMode.local;
  ConnectionActionState _state = ConnectionActionState.idle;
  bool _hasSavedCredential = false;
  String? _errorMessage;

  SessionMode get mode => _mode;
  ConnectionActionState get state => _state;
  bool get hasSavedCredential => _hasSavedCredential;
  String? get errorMessage => _errorMessage;
  bool get isBusy => _state == ConnectionActionState.connecting;

  Future<void> initialize() async {
    try {
      _hasSavedCredential =
          (await _credentialVault.readDiscordBotToken())?.isNotEmpty == true;
    } catch (_) {
      _hasSavedCredential = false;
    }
    notifyListeners();
  }

  Future<bool> connectWithBotToken({
    required String token,
    required bool remember,
  }) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      _state = ConnectionActionState.failure;
      _errorMessage = 'Enter a Discord application bot token.';
      notifyListeners();
      return false;
    }
    return _connect(normalized, remember: remember);
  }

  Future<bool> connectSavedCredential() async {
    try {
      final token = await _credentialVault.readDiscordBotToken();
      if (token == null || token.isEmpty) {
        _hasSavedCredential = false;
        _state = ConnectionActionState.failure;
        _errorMessage = 'Saved credential is no longer available.';
        notifyListeners();
        return false;
      }
      return _connect(token, remember: true);
    } catch (_) {
      _state = ConnectionActionState.failure;
      _errorMessage = 'Windows Credential Manager could not be read.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> _connect(String token, {required bool remember}) async {
    _state = ConnectionActionState.connecting;
    _errorMessage = null;
    notifyListeners();
    try {
      final repository = await _repositoryFactory.createDiscordRepository(
        token,
      );
      await _chatController.useRepository(repository);
    } catch (error) {
      await _chatController.useRepository(MockChatRepository());
      _mode = SessionMode.local;
      _state = ConnectionActionState.failure;
      _errorMessage = _messageFor(error);
      notifyListeners();
      return false;
    }
    _mode = SessionMode.discordBot;
    _state = ConnectionActionState.connected;
    try {
      if (remember) {
        await _credentialVault.writeDiscordBotToken(token);
        _hasSavedCredential = true;
      } else {
        await _credentialVault.clearDiscordBotToken();
        _hasSavedCredential = false;
      }
    } catch (_) {
      _hasSavedCredential = false;
      _errorMessage =
          'Connected, but Windows Credential Manager could not be updated.';
    }
    notifyListeners();
    return true;
  }

  Future<void> useLocalWorkspace() async {
    if (_mode != SessionMode.local ||
        _chatController.state == ChatLoadState.failure) {
      await _chatController.useRepository(MockChatRepository());
    }
    _mode = SessionMode.local;
    _state = ConnectionActionState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> forgetSavedCredential() async {
    await _credentialVault.clearDiscordBotToken();
    _hasSavedCredential = false;
    notifyListeners();
  }

  static String _messageFor(Object error) {
    if (error is DiscordApiException && error.isUnauthorized) {
      return 'Discord rejected this bot token.';
    }
    return 'Discord is unreachable. The local workspace was restored.';
  }
}
