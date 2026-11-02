import 'package:flutter/foundation.dart';

import '../data/disconnected_chat_repository.dart';
import '../data/discord/discord_api_client.dart';
import '../domain/chat_repository_factory.dart';
import '../domain/credential_vault.dart';
import '../domain/discord_session.dart';
import 'chat_controller.dart';
import '../app_log.dart';

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
  String? _errorDetail;

  SessionMode get mode => _mode;
  ConnectionActionState get state => _state;
  bool get hasSavedCredential => _hasSavedCredential;
  DiscordAccountSession? get activeSession => _activeSession;
  Set<DiscordSessionCapability> get capabilities =>
      _activeSession?.capabilities ?? const {};

  /// Why the last action failed, in plain words.
  String? get errorMessage => _errorMessage;

  /// What the failure said underneath [errorMessage], for a bug report.
  String? get errorDetail => _errorDetail;
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
      _fail(_unreadableVaultMessage);
      return;
    }
    if (session != null) {
      await _connect(session, remember: true, persistCredential: false);
      return;
    }
    await _ensureDisconnectedWorkspace();
    _mode = SessionMode.disconnected;
    _state = ConnectionActionState.idle;
    _clearError();
    notifyListeners();
  }

  Future<bool> connectWithBotToken({
    required String token,
    required bool remember,
  }) async {
    if (!botTransportEnabled) return _rejectDisabledBotTransport();
    final normalized = token.trim();
    if (normalized.isEmpty) {
      _fail('Enter a Discord application bot token.');
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
    _fail('Developer bot transport is disabled in this build.');
    return false;
  }

  Future<bool> connectSavedCredential() async {
    try {
      final session = await _credentialVault.readDiscordSession();
      if (session == null) {
        _hasSavedCredential = false;
        _fail('Saved credential is no longer available.');
        return false;
      }
      if (session is DiscordBotSession && !botTransportEnabled) {
        return _rejectDisabledBotTransport();
      }
      return _connect(session, remember: true, persistCredential: false);
    } catch (_) {
      _fail(_unreadableVaultMessage);
      return false;
    }
  }

  Future<bool> _connect(
    DiscordAccountSession session, {
    required bool remember,
    bool persistCredential = true,
  }) async {
    _state = ConnectionActionState.connecting;
    _clearError();
    notifyListeners();
    try {
      // Every repository of one account file shares one database handle, so a
      // live one must close first, or its close takes the new one's cache too.
      if (_mode == SessionMode.discord) {
        await _ensureDisconnectedWorkspace();
        _mode = SessionMode.disconnected;
        _activeSession = null;
      }
      final repository = await _repositoryFactory.create(session);
      await _chatController.useRepository(repository);
    } catch (error, stackTrace) {
      AppLog.error(
        'connection',
        'Discord connection bootstrap failed: ${_diagnosticFor(error)}',
        stackTrace: stackTrace,
      );
      await _ensureDisconnectedWorkspace();
      _mode = SessionMode.disconnected;
      _activeSession = null;
      _fail(_messageFor(error, session), detail: _detailFor(error));
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
    _clearError();
    notifyListeners();
  }

  Future<void> disconnectAndForget() async {
    await disconnect();
    await forgetSavedCredential();
  }

  /// Forgets the account on this machine: its credential and its cached data.
  ///
  /// A live session ends first, because it holds the cache open and would keep
  /// writing to it. A cache that cannot be cleared must not keep the credential
  /// alive, so the credential goes either way and the failure is reported.
  Future<void> forgetSavedCredential() async {
    if (_mode == SessionMode.discord) await disconnect();
    try {
      await _repositoryFactory.clearCache();
    } catch (error, stackTrace) {
      AppLog.error(
        'connection',
        'The chat cache could not be cleared: $error',
        stackTrace: stackTrace,
      );
      _errorMessage = 'Your cached messages could not be removed from disk.';
    }
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

  void _fail(String message, {String? detail}) {
    _state = ConnectionActionState.failure;
    _errorMessage = message;
    _errorDetail = detail;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    _errorDetail = null;
  }

  static const _unreadableVaultMessage =
      'Your saved sign-in could not be read.';

  static String _messageFor(Object error, DiscordAccountSession session) {
    if (error is UnsupportedDiscordSessionException) {
      return 'This Discord session cannot open chat. Please sign in again.';
    }
    if (error is DiscordApiException && error.isUnauthorized) {
      return 'Discord rejected this ${session.credentialLabel}.';
    }
    return 'Could not reach Discord. Check your connection.';
  }

  /// The failure's own words, kept apart from the plain [_messageFor]. Showing
  /// only one fixed sentence is what made two broken releases undiagnosable
  /// from the outside: the user could only report "unreachable".
  static String? _detailFor(Object error) => switch (error) {
    UnsupportedDiscordSessionException() => null,
    DiscordApiException(isUnauthorized: true) => null,
    DiscordApiException() => error.message,
    _ => '${error.runtimeType}',
  };

  static String _diagnosticFor(Object error) => switch (error) {
    DiscordApiException() =>
      'DiscordApiException(status=${error.statusCode}, message=${error.message})',
    _ => '${error.runtimeType}: $error',
  };
}
