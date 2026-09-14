import 'package:flutter/foundation.dart';

import '../domain/discord_relationship.dart';
import '../domain/discord_social_presence.dart';
import '../domain/discord_social_sdk.dart';

enum DiscordSocialPresenceState { unavailable, ready, updating, failure }

final class DiscordSocialPresenceController extends ChangeNotifier {
  DiscordSocialPresenceController(this._gateway);

  final DiscordSocialPresenceGateway? _gateway;

  DiscordSocialPresenceState _state = DiscordSocialPresenceState.unavailable;
  DiscordOnlineStatus _status = DiscordOnlineStatus.online;
  DiscordOnlineStatus? _pendingStatus;
  String? _errorCode;
  bool _sessionReady = false;
  bool _hasConfirmedStatus = false;
  bool _disposed = false;
  int _generation = 0;

  DiscordSocialPresenceState get state => _state;
  DiscordOnlineStatus get status => _status;
  DiscordOnlineStatus? get pendingStatus => _pendingStatus;
  String? get errorCode => _errorCode;
  bool get canUpdate =>
      _sessionReady &&
      _gateway != null &&
      _state != DiscordSocialPresenceState.updating;

  void reconcileSession(
    DiscordSocialSdkAvailability? availability, {
    required bool authenticated,
  }) {
    final sessionReady =
        availability?.isReady == true && authenticated && _gateway != null;
    if (_sessionReady == sessionReady) return;
    _sessionReady = sessionReady;
    _generation++;
    _pendingStatus = null;
    _errorCode = null;
    _hasConfirmedStatus = false;
    _state = sessionReady
        ? DiscordSocialPresenceState.ready
        : DiscordSocialPresenceState.unavailable;
    if (!_disposed) notifyListeners();
  }

  Future<bool> setStatus(DiscordOnlineStatus status) async {
    final gateway = _gateway;
    if (!canUpdate || gateway == null) return false;
    if (_hasConfirmedStatus &&
        status == _status &&
        _state == DiscordSocialPresenceState.ready) {
      return true;
    }
    final generation = _generation;
    _pendingStatus = status;
    _errorCode = null;
    _state = DiscordSocialPresenceState.updating;
    notifyListeners();
    try {
      await gateway.setOnlineStatus(status);
      if (!_accepts(generation)) return false;
      _status = status;
      _hasConfirmedStatus = true;
      _state = DiscordSocialPresenceState.ready;
      return true;
    } on DiscordSocialSdkException catch (error) {
      if (!_accepts(generation)) return false;
      _errorCode = error.code;
      _state = DiscordSocialPresenceState.failure;
      return false;
    } on Object {
      if (!_accepts(generation)) return false;
      _errorCode = 'status_update_failure';
      _state = DiscordSocialPresenceState.failure;
      return false;
    } finally {
      if (_accepts(generation)) {
        _pendingStatus = null;
        notifyListeners();
      }
    }
  }

  bool _accepts(int generation) =>
      !_disposed && _sessionReady && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
