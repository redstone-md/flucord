import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/discord_relationship.dart';
import '../domain/discord_social_sdk.dart';

enum DiscordSocialSdkControllerState {
  idle,
  checking,
  restoring,
  signedOut,
  authorizing,
  ready,
  unconfigured,
  disconnecting,
  unavailable,
  failure,
}

final class DiscordSocialSdkController extends ChangeNotifier {
  DiscordSocialSdkController(this._gateway) {
    if (_gateway case final DiscordSocialSdkAuthenticationEvents events) {
      _authenticationSubscription = events.authenticationChanges.listen(
        _onAuthenticationChanged,
      );
    }
  }

  final DiscordSocialSdkGateway _gateway;
  StreamSubscription<DiscordSocialSdkAuthentication>?
  _authenticationSubscription;

  DiscordSocialSdkControllerState _state = DiscordSocialSdkControllerState.idle;
  DiscordSocialSdkAvailability? _availability;
  String? _failureCode;
  String? _authenticatedUserId;
  Future<void>? _inFlight;
  bool _initialized = false;
  bool _disposed = false;
  int _generation = 0;

  DiscordSocialSdkControllerState get state => _state;
  DiscordSocialSdkAvailability? get availability => _availability;
  String? get failureCode => _failureCode;
  String? get authenticatedUserId => _authenticatedUserId;
  bool get isAuthenticated => _state == DiscordSocialSdkControllerState.ready;

  Future<void> initialize() {
    if (_initialized) return _inFlight ?? Future<void>.value();
    _initialized = true;
    return _start(_initialize);
  }

  Future<void> retry() => _start(_initialize);

  Future<void> authorize() {
    if (_availability?.isReady != true || _disposed) {
      return Future<void>.value();
    }
    return _start(_authorize);
  }

  Future<void> disconnect() {
    if (_disposed) return Future<void>.value();
    return _start(_disconnect);
  }

  Future<void> _start(Future<void> Function() operation) {
    if (_disposed) return Future<void>.value();
    return _inFlight ??= operation().whenComplete(() => _inFlight = null);
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    _failureCode = null;
    _state = DiscordSocialSdkControllerState.checking;
    notifyListeners();
    DiscordSocialSdkAvailability availability;
    try {
      availability = await _gateway.checkAvailability();
    } on Object {
      availability = DiscordSocialSdkAvailability.failure('gateway_failure');
    }
    if (!_accepts(generation)) return;
    _availability = availability;
    if (!availability.isReady) {
      _state = switch (availability.status) {
        DiscordSocialSdkAvailabilityStatus.sdkNotBundled ||
        DiscordSocialSdkAvailabilityStatus.unsupportedPlatform =>
          DiscordSocialSdkControllerState.unavailable,
        DiscordSocialSdkAvailabilityStatus.failure =>
          DiscordSocialSdkControllerState.failure,
        DiscordSocialSdkAvailabilityStatus.ready =>
          DiscordSocialSdkControllerState.restoring,
      };
      _failureCode =
          availability.status == DiscordSocialSdkAvailabilityStatus.failure
          ? availability.diagnosticCode
          : null;
      notifyListeners();
      return;
    }
    _state = DiscordSocialSdkControllerState.restoring;
    notifyListeners();
    try {
      final authentication = await _gateway.restoreAuthentication();
      if (!_accepts(generation)) return;
      _applyAuthentication(authentication);
    } on DiscordSocialSdkException catch (error) {
      if (!_accepts(generation)) return;
      _fail(error.code);
    } on Object {
      if (!_accepts(generation)) return;
      _fail('authentication_restore_failed');
    }
    notifyListeners();
  }

  Future<void> _authorize() async {
    final generation = ++_generation;
    _failureCode = null;
    _state = DiscordSocialSdkControllerState.authorizing;
    notifyListeners();
    try {
      final authentication = await _gateway.authorize();
      if (!_accepts(generation)) return;
      _applyAuthentication(authentication);
    } on DiscordSocialSdkException catch (error) {
      if (!_accepts(generation)) return;
      _fail(error.code);
    } on Object {
      if (!_accepts(generation)) return;
      _fail('authorization_failed');
    }
    notifyListeners();
  }

  Future<void> _disconnect() async {
    final generation = ++_generation;
    _failureCode = null;
    _state = DiscordSocialSdkControllerState.disconnecting;
    notifyListeners();
    try {
      await _gateway.disconnect();
      if (!_accepts(generation)) return;
      _authenticatedUserId = null;
      _state = DiscordSocialSdkControllerState.signedOut;
    } on DiscordSocialSdkException catch (error) {
      if (!_accepts(generation)) return;
      _fail(error.code);
    } on Object {
      if (!_accepts(generation)) return;
      _fail('disconnect_failed');
    }
    notifyListeners();
  }

  void _applyAuthentication(DiscordSocialSdkAuthentication authentication) {
    _failureCode = null;
    _authenticatedUserId = authentication.isReady
        ? authentication.userId
        : null;
    _state = switch (authentication.status) {
      DiscordSocialSdkAuthenticationStatus.ready =>
        DiscordSocialSdkControllerState.ready,
      DiscordSocialSdkAuthenticationStatus.signedOut =>
        DiscordSocialSdkControllerState.signedOut,
      DiscordSocialSdkAuthenticationStatus.unconfigured =>
        DiscordSocialSdkControllerState.unconfigured,
    };
  }

  void _fail(String code) {
    _failureCode = code.trim().isEmpty ? 'unknown_failure' : code.trim();
    _authenticatedUserId = null;
    _state = DiscordSocialSdkControllerState.failure;
  }

  bool _accepts(int generation) => !_disposed && generation == _generation;

  void _onAuthenticationChanged(DiscordSocialSdkAuthentication authentication) {
    if (_disposed || _availability?.isReady != true) return;
    _generation++;
    _applyAuthentication(authentication);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_authenticationSubscription?.cancel());
    super.dispose();
  }
}
