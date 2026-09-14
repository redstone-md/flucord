import 'package:flutter/foundation.dart';

import '../domain/discord_oauth.dart';

enum DiscordOAuthLinkState {
  unavailable,
  idle,
  restoring,
  authorizing,
  linked,
  failure,
}

final class DiscordOAuthController extends ChangeNotifier {
  DiscordOAuthController(this._gateway)
    : _state = _gateway.isConfigured
          ? DiscordOAuthLinkState.idle
          : DiscordOAuthLinkState.unavailable;

  final DiscordOAuthAccountGateway _gateway;

  DiscordOAuthLinkState _state;
  DiscordOAuthAccount? _account;
  String? _errorMessage;

  DiscordOAuthLinkState get state => _state;
  DiscordOAuthAccount? get account => _account;
  String? get errorMessage => _errorMessage;
  bool get isConfigured => _gateway.isConfigured;
  bool get isBusy =>
      _state == DiscordOAuthLinkState.restoring ||
      _state == DiscordOAuthLinkState.authorizing;

  Future<void> initialize() async {
    if (!_gateway.isConfigured) return;
    _state = DiscordOAuthLinkState.restoring;
    _errorMessage = null;
    notifyListeners();
    try {
      _account = await _gateway.restore();
      _state = _account == null
          ? DiscordOAuthLinkState.idle
          : DiscordOAuthLinkState.linked;
    } on Object catch (error) {
      _state = DiscordOAuthLinkState.failure;
      _errorMessage = _messageFor(error);
    }
    notifyListeners();
  }

  Future<bool> authorize() async {
    if (!_gateway.isConfigured || isBusy) return false;
    _state = DiscordOAuthLinkState.authorizing;
    _errorMessage = null;
    notifyListeners();
    try {
      _account = await _gateway.authorize();
      _state = DiscordOAuthLinkState.linked;
      notifyListeners();
      return true;
    } on Object catch (error) {
      _state = DiscordOAuthLinkState.failure;
      _errorMessage = _messageFor(error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> handleProtocolUri(Uri uri) => _gateway.handleRedirect(uri);

  Future<void> unlink() async {
    try {
      await _gateway.clear();
      _account = null;
      _state = DiscordOAuthLinkState.idle;
      _errorMessage = null;
    } on Object {
      _state = DiscordOAuthLinkState.failure;
      _errorMessage = 'The Discord OAuth credential could not be removed.';
    }
    notifyListeners();
  }

  static String _messageFor(Object error) => error is DiscordOAuthException
      ? error.message
      : 'Discord account linking failed.';

  @override
  void dispose() {
    _gateway.dispose();
    super.dispose();
  }
}
