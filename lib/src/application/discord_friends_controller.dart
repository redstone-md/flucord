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
  final Set<String> _mutatingUserIds = {};
  final Map<String, String> _mutationErrors = {};
  Future<void>? _inFlight;
  bool _sdkReady = false;
  bool _authenticated = false;
  bool _initialized = false;
  bool _disposed = false;
  int _generation = 0;

  DiscordFriendsLoadState get state => _state;
  List<DiscordRelationship> get relationships => _relationships;
  bool isMutating(String userId) => _mutatingUserIds.contains(userId);
  String? mutationErrorFor(String userId) => _mutationErrors[userId];

  void reconcileSession(
    DiscordSocialSdkAvailability? availability, {
    required bool authenticated,
  }) {
    final sdkReady = availability?.isReady ?? false;
    if (_sdkReady == sdkReady && _authenticated == authenticated) return;
    _sdkReady = sdkReady;
    _authenticated = sdkReady && authenticated;
    _initialized = false;
    _generation++;
    _inFlight = null;
    _mutatingUserIds.clear();
    _mutationErrors.clear();
    if (!sdkReady) {
      _relationships = const [];
      _state = DiscordFriendsLoadState.unavailable;
      if (!_disposed) notifyListeners();
      return;
    }
    if (!_authenticated) {
      _relationships = const [];
      _state = DiscordFriendsLoadState.authorizationRequired;
      if (!_disposed) notifyListeners();
      return;
    }
    _state = DiscordFriendsLoadState.idle;
    if (!_disposed) notifyListeners();
    unawaited(initialize());
  }

  Future<void> initialize() {
    if (_initialized || !_sdkReady || !_authenticated || _disposed) {
      return _inFlight ?? Future<void>.value();
    }
    _initialized = true;
    return _startLoad();
  }

  Future<void> retry() =>
      _sdkReady && _authenticated ? _startLoad() : Future<void>.value();

  Future<bool> updateRelationship(
    DiscordRelationship relationship,
    DiscordRelationshipAction action,
  ) async {
    final userId = relationship.user.id;
    if (_disposed ||
        _state != DiscordFriendsLoadState.ready ||
        !relationship.supports(action) ||
        _mutatingUserIds.contains(userId)) {
      return false;
    }
    final generation = _generation;
    _mutatingUserIds.add(userId);
    _mutationErrors.remove(userId);
    notifyListeners();
    var succeeded = false;
    try {
      await _gateway.updateRelationship(userId: userId, action: action);
      if (!_accepts(generation)) return false;
      _applyConfirmedMutation(userId, action);
      succeeded = true;
    } on DiscordSocialSdkException catch (error) {
      if (!_accepts(generation)) return false;
      _mutationErrors[userId] = error.code;
    } on Object {
      if (!_accepts(generation)) return false;
      _mutationErrors[userId] = 'mutation_failure';
    } finally {
      if (!_disposed && generation == _generation) {
        _mutatingUserIds.remove(userId);
        notifyListeners();
      }
    }
    return succeeded;
  }

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
      _mutationErrors.clear();
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
      !_disposed && _sdkReady && _authenticated && generation == _generation;

  void _applyConfirmedMutation(
    String userId,
    DiscordRelationshipAction action,
  ) {
    final updated = <DiscordRelationship>[];
    for (final relationship in _relationships) {
      if (relationship.user.id != userId) {
        updated.add(relationship);
      } else if (action == DiscordRelationshipAction.acceptRequest) {
        updated.add(relationship.withKind(DiscordRelationshipKind.friend));
      }
    }
    updated.sort(_compareRelationships);
    _relationships = List.unmodifiable(updated);
    _mutationErrors.remove(userId);
  }

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
    _mutatingUserIds.clear();
    _mutationErrors.clear();
    super.dispose();
  }
}
