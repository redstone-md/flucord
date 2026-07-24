import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/discord_relationship.dart';
import '../domain/discord_social_sdk.dart';

enum DiscordFriendsLoadState {
  idle,
  loading,
  ready,
  authorizationRequired,
  unavailable,
  failure,
}

final class DiscordFriendsController extends ChangeNotifier {
  DiscordFriendsController(this._gateway);

  final DiscordSocialSdkGateway _gateway;

  DiscordFriendsLoadState _state = DiscordFriendsLoadState.idle;
  List<DiscordRelationship> _relationships = const [];
  Future<void>? _inFlight;
  bool _sdkReady = false;
  bool _initialized = false;
  bool _disposed = false;
  int _generation = 0;

  DiscordFriendsLoadState get state => _state;
  List<DiscordRelationship> get relationships => _relationships;

  void reconcileAvailability(DiscordSocialSdkAvailability? availability) {
    final sdkReady = availability?.isReady ?? false;
    if (_sdkReady == sdkReady) return;
    _sdkReady = sdkReady;
    _initialized = false;
    _generation++;
    _inFlight = null;
    if (!sdkReady) {
      _relationships = const [];
      _state = DiscordFriendsLoadState.unavailable;
      if (!_disposed) notifyListeners();
      return;
    }
    _state = DiscordFriendsLoadState.idle;
    if (!_disposed) notifyListeners();
    unawaited(initialize());
  }

  Future<void> initialize() {
    if (_initialized || !_sdkReady || _disposed) {
      return _inFlight ?? Future<void>.value();
    }
    _initialized = true;
    return _startLoad();
  }

  Future<void> retry() => _sdkReady ? _startLoad() : Future<void>.value();

  Future<void> _startLoad() {
    if (_disposed) return Future<void>.value();
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _state = DiscordFriendsLoadState.loading;
    notifyListeners();
    try {
      final relationships = await _gateway.fetchRelationships();
      if (!_accepts(generation)) return;
      _relationships = List.unmodifiable(
        <DiscordRelationship>[...relationships]..sort(_compareRelationships),
      );
      _state = DiscordFriendsLoadState.ready;
    } on DiscordSocialSdkException catch (error) {
      if (!_accepts(generation)) return;
      _relationships = const [];
      _state = switch (error.code) {
        'not_authenticated' => DiscordFriendsLoadState.authorizationRequired,
        'sdk_not_bundled' ||
        'unsupported_platform' => DiscordFriendsLoadState.unavailable,
        _ => DiscordFriendsLoadState.failure,
      };
    } on Object {
      if (!_accepts(generation)) return;
      _relationships = const [];
      _state = DiscordFriendsLoadState.failure;
    }
    notifyListeners();
  }

  bool _accepts(int generation) =>
      !_disposed && _sdkReady && generation == _generation;

  static int _compareRelationships(
    DiscordRelationship left,
    DiscordRelationship right,
  ) => left.user.displayName.toLowerCase().compareTo(
    right.user.displayName.toLowerCase(),
  );

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _relationships = const [];
    super.dispose();
  }
}
