import 'package:flutter/foundation.dart';

import '../domain/discord_social_sdk.dart';

enum DiscordSocialSdkControllerState {
  idle,
  checking,
  ready,
  unavailable,
  failure,
}

final class DiscordSocialSdkController extends ChangeNotifier {
  DiscordSocialSdkController(this._gateway);

  final DiscordSocialSdkGateway _gateway;

  DiscordSocialSdkControllerState _state = DiscordSocialSdkControllerState.idle;
  DiscordSocialSdkAvailability? _availability;
  Future<void>? _inFlight;
  bool _initialized = false;
  bool _disposed = false;
  int _generation = 0;

  DiscordSocialSdkControllerState get state => _state;
  DiscordSocialSdkAvailability? get availability => _availability;

  Future<void> initialize() {
    if (_initialized) return _inFlight ?? Future<void>.value();
    _initialized = true;
    return _startCheck();
  }

  Future<void> retry() => _startCheck();

  Future<void> _startCheck() {
    if (_disposed) return Future<void>.value();
    return _inFlight ??= _check().whenComplete(() => _inFlight = null);
  }

  Future<void> _check() async {
    final generation = ++_generation;
    _state = DiscordSocialSdkControllerState.checking;
    notifyListeners();
    DiscordSocialSdkAvailability availability;
    try {
      availability = await _gateway.checkAvailability();
    } on Object {
      availability = DiscordSocialSdkAvailability.failure('gateway_failure');
    }
    if (_disposed || generation != _generation) return;
    _availability = availability;
    _state = switch (availability.status) {
      DiscordSocialSdkAvailabilityStatus.ready =>
        DiscordSocialSdkControllerState.ready,
      DiscordSocialSdkAvailabilityStatus.sdkNotBundled ||
      DiscordSocialSdkAvailabilityStatus.unsupportedPlatform =>
        DiscordSocialSdkControllerState.unavailable,
      DiscordSocialSdkAvailabilityStatus.failure =>
        DiscordSocialSdkControllerState.failure,
    };
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
