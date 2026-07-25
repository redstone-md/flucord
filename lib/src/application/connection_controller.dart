import 'package:flutter/foundation.dart';

import '../data/disconnected_chat_repository.dart';
import '../data/discord/discord_api_client.dart';
import '../domain/chat_repository_factory.dart';
import '../domain/credential_vault.dart';
import '../domain/discord_session.dart';
import 'chat_controller.dart';

enum SessionMode { disconnected, demo, discord }

enum ConnectionActionState { idle, connecting, connected, failure }

final class ConnectionController extends ChangeNotifier {
  ConnectionController(
    this._chatController,
    this._credentialVault,
    this._repositoryFactory, {
    SessionMode initialMode = SessionMode.disconnected,
    this.botTransportEnabled = false,
  }) : _mode = initialMode;

  final ChatController _chatController;
  final CredentialVault _credentialVault;
  final ChatRepositoryFactory _repositoryFactory;
  final bool botTransportEnabled;

  SessionMode _mode;
  ConnectionActionState _state = ConnectionActionState.idle;
  bool _hasSavedCredential = false;
  DiscordAccountSession? _activeSession;
  String? _errorMessage;

  SessionMode get mode => _mode;
  ConnectionActionState get state => _state;
  bool get hasSavedCredential => _hasSavedCredential;
  DiscordAccountSession? get activeSession => _activeSession;
  Set<DiscordSessionCapability> get capabilities =>
      _activeSession?.capabilities ?? const {};
  String? get errorMessage => _errorMessage;
  bool get isBusy => _state == ConnectionActionState.connecting;

  Future<void> initialize({bool restoreSavedSession = true}) async {
    if (!restoreSavedSession) {
      await _chatController.load();
      notifyListeners();
      return;
    }
    DiscordAccountSession? session;
    try {
      session = await _credentialVault.readDiscordSession();
      if (session is DiscordBotSession && !botTransportEnabled) {
        session = null;
      }
      _hasSavedCredential = session != null;
    } catch (_) {
      _hasSavedCredential = false;
      await _ensureDisconnectedWorkspace();
      _mode = SessionMode.disconnected;
      _state = ConnectionActionState.failure;
      _errorMessage = 'The system credential vault could not be read.';
      notifyListeners();
      return;
    }
    if (session != null) {
      await _connect(session, remember: true, persistCredential: false);
      return;
    }
    await _ensureDisconnectedWorkspace();
    _mode = SessionMode.disconnected;
    _state = ConnectionActionState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> connectWithBotToken({
    required String token,
    required bool remember,
  }) async {
    if (!botTransportEnabled) return _rejectDisabledBotTransport();
    final normalized = token.trim();
    if (normalized.isEmpty) {
      _state = ConnectionActionState.failure;
      _errorMessage = 'Enter a Discord application bot token.';
      notifyListeners();
      return false;
    }
    return connectSession(
      session: DiscordBotSession(normalized),
      remember: remember,
    );
  }

  Future<bool> connectSession({
    required DiscordAccountSession session,
    required bool remember,
  }) {
    if (session is DiscordBotSession && !botTransportEnabled) {
      return _rejectDisabledBotTransport();
    }
    return _connect(session, remember: remember);
  }

  Future<bool> _rejectDisabledBotTransport() async {
    _state = ConnectionActionState.failure;
    _errorMessage = 'Developer bot transport is disabled in this build.';
    notifyListeners();
    return false;
  }

  Future<bool> connectSavedCredential() async {
    try {
      final session = await _credentialVault.readDiscordSession();
      if (session == null) {
        _hasSavedCredential = false;
        _state = ConnectionActionState.failure;
        _errorMessage = 'Saved credential is no longer available.';
        notifyListeners();
        return false;
      }
      if (session is DiscordBotSession && !botTransportEnabled) {
        return _rejectDisabledBotTransport();
      }
      return _connect(session, remember: true, persistCredential: false);
    } catch (_) {
      _state = ConnectionActionState.failure;
      _errorMessage = 'The system credential vault could not be read.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> _connect(
    DiscordAccountSession session, {
    required bool remember,
    bool persistCredential = true,
  }) async {
    _state = ConnectionActionState.connecting;
    _errorMessage = null;
    notifyListeners();
    try {
      final repository = await _repositoryFactory.create(session);
      await _chatController.useRepository(repository);
    } catch (error) {
      await _ensureDisconnectedWorkspace();
      _mode = SessionMode.disconnected;
      _activeSession = null;
      _state = ConnectionActionState.failure;
      _errorMessage = _messageFor(error, session);
      notifyListeners();
      return false;
    }
    _mode = SessionMode.discord;
    _activeSession = session;
    _state = ConnectionActionState.connected;
    if (!persistCredential) {
      _hasSavedCredential = remember;
      notifyListeners();
      return true;
    }
    try {
      if (remember) {
        await _credentialVault.writeDiscordSession(session);
        _hasSavedCredential = true;
      } else {
        await _credentialVault.clearDiscordSession();
        _hasSavedCredential = false;
      }
    } catch (_) {
      _hasSavedCredential = false;
      _errorMessage =
          'Connected, but the system credential vault could not be updated.';
    }
    notifyListeners();
    return true;
  }

  Future<void> disconnect() async {
    await _ensureDisconnectedWorkspace();
    _mode = SessionMode.disconnected;
    _activeSession = null;
    _state = ConnectionActionState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> disconnectAndForget() async {
    await disconnect();
    await forgetSavedCredential();
  }

  Future<void> forgetSavedCredential() async {
    await _credentialVault.clearDiscordSession();
    _hasSavedCredential = false;
    notifyListeners();
  }

  Future<void> _ensureDisconnectedWorkspace() async {
    if (_mode == SessionMode.disconnected &&
        _chatController.state != ChatLoadState.failure) {
      if (_chatController.state == ChatLoadState.idle) {
        await _chatController.load();
      }
      if (_chatController.state == ChatLoadState.ready &&
          _chatController.workspace?.spaces.isEmpty == true) {
        return;
      }
    }
    await _chatController.useRepository(const DisconnectedChatRepository());
  }

  static String _messageFor(Object error, DiscordAccountSession session) {
    if (error is UnsupportedDiscordSessionException) {
      return 'This authorized Discord session does not expose full chat and Gateway access.';
    }
    if (error is DiscordApiException && error.isUnauthorized) {
      return 'Discord rejected this ${session.credentialLabel}.';
    }
    return 'Discord is unreachable. No chat transport is connected.';
  }
}
