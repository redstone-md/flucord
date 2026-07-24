import 'package:flutter/foundation.dart';

import '../domain/discord_oauth.dart';
import 'discord_oauth_controller.dart';
import 'discord_social_sdk_controller.dart';

enum DiscordAccountConnectionState {
  unavailable,
  disconnected,
  connecting,
  partiallyConnected,
  connected,
  disconnecting,
  failure,
}

final class DiscordAccountConnectionController extends ChangeNotifier {
  DiscordAccountConnectionController(
    this._oauthController,
    this._socialController,
  ) {
    _oauthController.addListener(_handleDependencyChanged);
    _socialController.addListener(_handleDependencyChanged);
  }

  final DiscordOAuthController _oauthController;
  final DiscordSocialSdkController _socialController;

  _DiscordAccountConnectionAction _action =
      _DiscordAccountConnectionAction.idle;
  String? _errorMessage;
  bool _disposed = false;

  DiscordOAuthAccount? get account => _oauthController.account;
  String? get errorMessage => _errorMessage;
  bool get oauthConfigured => _oauthController.isConfigured;
  bool get oauthLinked => _oauthController.account != null;
  bool get socialAvailable => _socialController.availability?.isReady == true;
  bool get socialConfigured =>
      _socialController.state != DiscordSocialSdkControllerState.unconfigured;
  bool get socialConnected => _socialController.isAuthenticated;
  bool get needsOAuth => oauthConfigured && !oauthLinked;
  bool get needsSocial =>
      socialAvailable && socialConfigured && !socialConnected;
  bool get isConnected => oauthLinked || socialConnected;
  bool get isFullyConnected => isConnected && !needsOAuth && !needsSocial;
  bool get canConnect => !isBusy && (needsOAuth || needsSocial);
  bool get canDisconnect => !isBusy && isConnected;

  bool get isBusy =>
      _action != _DiscordAccountConnectionAction.idle ||
      _oauthController.isBusy ||
      _socialController.state == DiscordSocialSdkControllerState.checking ||
      _socialController.state == DiscordSocialSdkControllerState.restoring ||
      _socialController.state == DiscordSocialSdkControllerState.authorizing ||
      _socialController.state == DiscordSocialSdkControllerState.disconnecting;

  DiscordAccountConnectionState get state {
    if (_action == _DiscordAccountConnectionAction.connecting ||
        (_action == _DiscordAccountConnectionAction.idle &&
            (_oauthController.isBusy ||
                _socialController.state ==
                    DiscordSocialSdkControllerState.checking ||
                _socialController.state ==
                    DiscordSocialSdkControllerState.restoring ||
                _socialController.state ==
                    DiscordSocialSdkControllerState.authorizing))) {
      return DiscordAccountConnectionState.connecting;
    }
    if (_action == _DiscordAccountConnectionAction.disconnecting ||
        _socialController.state ==
            DiscordSocialSdkControllerState.disconnecting) {
      return DiscordAccountConnectionState.disconnecting;
    }
    if (_errorMessage != null) return DiscordAccountConnectionState.failure;
    if (isFullyConnected) return DiscordAccountConnectionState.connected;
    if (isConnected) {
      return DiscordAccountConnectionState.partiallyConnected;
    }
    if (!oauthConfigured && (!socialAvailable || !socialConfigured)) {
      return DiscordAccountConnectionState.unavailable;
    }
    return DiscordAccountConnectionState.disconnected;
  }

  Future<bool> connect() async {
    if (_disposed || isBusy || (!needsOAuth && !needsSocial)) {
      return isFullyConnected;
    }
    _action = _DiscordAccountConnectionAction.connecting;
    _errorMessage = null;
    notifyListeners();

    if (needsOAuth) {
      final linked = await _oauthController.authorize();
      if (_disposed) return false;
      if (!linked) {
        _errorMessage =
            _oauthController.errorMessage ?? 'Discord authorization failed.';
        return _finishAction(false);
      }
    }

    if (needsSocial) {
      await _socialController.authorize();
      if (_disposed) return false;
      if (!_socialController.isAuthenticated) {
        _errorMessage = _socialFailureMessage();
        return _finishAction(false);
      }
    }

    return _finishAction(isFullyConnected);
  }

  Future<bool> disconnect() async {
    if (_disposed || isBusy || !isConnected) return !isConnected;
    _action = _DiscordAccountConnectionAction.disconnecting;
    _errorMessage = null;
    notifyListeners();

    var failed = false;
    if (socialAvailable && socialConfigured) {
      await _socialController.disconnect();
      if (_disposed) return false;
      failed =
          _socialController.state == DiscordSocialSdkControllerState.failure;
    }
    if (oauthLinked) {
      await _oauthController.unlink();
      if (_disposed) return false;
      failed =
          failed ||
          _oauthController.state == DiscordOAuthLinkState.failure ||
          _oauthController.account != null;
    }
    if (failed) {
      _errorMessage = 'One Discord authorization could not be disconnected.';
    }
    return _finishAction(!failed && !isConnected);
  }

  bool _finishAction(bool result) {
    if (_disposed) return false;
    _action = _DiscordAccountConnectionAction.idle;
    notifyListeners();
    return result;
  }

  String _socialFailureMessage() => switch (_socialController.failureCode) {
    'authorization_cancelled' => 'Discord authorization was cancelled.',
    'not_authenticated' => 'Discord social authorization did not complete.',
    _ => 'Discord social authorization failed.',
  };

  void _handleDependencyChanged() {
    if (_disposed) return;
    if (_action == _DiscordAccountConnectionAction.idle && isFullyConnected) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _oauthController.removeListener(_handleDependencyChanged);
    _socialController.removeListener(_handleDependencyChanged);
    super.dispose();
  }
}

enum _DiscordAccountConnectionAction { idle, connecting, disconnecting }
