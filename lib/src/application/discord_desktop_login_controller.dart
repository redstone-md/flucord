import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/discord_remote_auth.dart';
import 'connection_controller.dart';

enum DiscordDesktopLoginState {
  idle,
  starting,
  qrReady,
  scanned,
  captchaRequired,
  connecting,
  connected,
  failure,
}

final class DiscordDesktopLoginController extends ChangeNotifier {
  DiscordDesktopLoginController(
    this._gatewayFactory,
    this._connectionController,
  );

  final DiscordRemoteAuthGatewayFactory _gatewayFactory;
  final ConnectionController _connectionController;

  DiscordRemoteAuthGateway? _gateway;
  StreamSubscription<DiscordRemoteAuthEvent>? _subscription;
  DiscordDesktopLoginState _state = DiscordDesktopLoginState.idle;
  Uri? _qrUri;
  String? _pendingDisplayName;
  String? _errorMessage;
  DiscordRemoteAuthCaptchaChallenge? _captchaChallenge;

  DiscordDesktopLoginState get state => _state;
  Uri? get qrUri => _qrUri;
  String? get pendingDisplayName => _pendingDisplayName;
  String? get errorMessage => _errorMessage;
  DiscordRemoteAuthCaptchaChallenge? get captchaChallenge => _captchaChallenge;
  bool get isBusy => switch (_state) {
    DiscordDesktopLoginState.starting ||
    DiscordDesktopLoginState.qrReady ||
    DiscordDesktopLoginState.scanned ||
    DiscordDesktopLoginState.captchaRequired ||
    DiscordDesktopLoginState.connecting => true,
    _ => false,
  };

  Future<void> start() async {
    await _disposeGateway();
    _state = DiscordDesktopLoginState.starting;
    _qrUri = null;
    _pendingDisplayName = null;
    _errorMessage = null;
    _captchaChallenge = null;
    notifyListeners();
    final gateway = _gatewayFactory.create();
    _gateway = gateway;
    _subscription = gateway.events.listen(_accept);
    await gateway.start();
  }

  void _accept(DiscordRemoteAuthEvent event) {
    switch (event) {
      case DiscordRemoteAuthQrReady():
        _qrUri = event.qrUri;
        _state = DiscordDesktopLoginState.qrReady;
        notifyListeners();
      case DiscordRemoteAuthUserPending():
        _pendingDisplayName = event.displayName;
        _state = DiscordDesktopLoginState.scanned;
        notifyListeners();
      case DiscordRemoteAuthCompleted():
        _captchaChallenge = null;
        _state = DiscordDesktopLoginState.connecting;
        notifyListeners();
        unawaited(_connect(event));
      case DiscordRemoteAuthCaptchaRequired():
        _captchaChallenge = event.challenge;
        _state = DiscordDesktopLoginState.captchaRequired;
        notifyListeners();
      case DiscordRemoteAuthFailed():
        _state = DiscordDesktopLoginState.failure;
        _errorMessage = event.message;
        notifyListeners();
    }
  }

  Future<void> submitCaptcha(String response) async {
    final gateway = _gateway;
    if (gateway == null || _state != DiscordDesktopLoginState.captchaRequired) {
      return;
    }
    await gateway.submitCaptcha(response);
  }

  Future<void> _connect(DiscordRemoteAuthCompleted event) async {
    final connected = await _connectionController.connectSession(
      session: event.session,
      remember: true,
    );
    _state = connected
        ? DiscordDesktopLoginState.connected
        : DiscordDesktopLoginState.failure;
    _errorMessage = connected ? null : _connectionController.errorMessage;
    await _disposeGateway();
    notifyListeners();
  }

  Future<void> cancel() async {
    await _disposeGateway();
    _state = DiscordDesktopLoginState.idle;
    _qrUri = null;
    _pendingDisplayName = null;
    _errorMessage = null;
    _captchaChallenge = null;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _connectionController.disconnectAndForget();
    _state = DiscordDesktopLoginState.idle;
    _qrUri = null;
    _pendingDisplayName = null;
    _errorMessage = null;
    _captchaChallenge = null;
    notifyListeners();
  }

  Future<void> _disposeGateway() async {
    await _subscription?.cancel();
    _subscription = null;
    await _gateway?.close();
    _gateway = null;
  }

  @override
  void dispose() {
    unawaited(_disposeGateway());
    super.dispose();
  }
}
