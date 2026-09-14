import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/chat_models.dart';
import '../domain/presence_repository.dart';

/// Holds the account's own presence for the chrome that renders and edits it.
///
/// The presence plane belongs to whichever transport is signed in, and that is
/// replaced when the session changes, so the service is resolved lazily rather
/// than captured once. Everything the picker shows is read back from the
/// service instead of being remembered here: a status set from another device
/// arrives as a settings dispatch, and a controller that trusted its own last
/// write would keep showing a choice the account no longer carries.
final class SelfPresenceController extends ChangeNotifier {
  SelfPresenceController(this._serviceProvider);

  final PresenceService? Function() _serviceProvider;

  PresenceService? _service;
  StreamSubscription<SelfPresence>? _updates;
  Object? _lastError;
  bool _bound = false;
  bool _disposed = false;

  /// Whether the signed-in transport can broadcast a status at all.
  bool get isAvailable => _service != null;

  /// Whether a write would reach Discord. False until the settings blob has
  /// arrived, because the status group cannot be edited before it is known.
  bool get canEdit => _service?.canEdit ?? false;

  /// What is on the wire, idle promotion included.
  SelfPresence get presence => _service?.selfPresence ?? const SelfPresence();

  /// What the user picked, which is what the menu ticks.
  Presence get chosenStatus => _service?.chosenStatus ?? Presence.online;

  UserActivity? get customStatus => _service?.customStatus;

  List<UserSession> get sessions => _service?.sessions ?? const [];

  /// Why the last edit failed, or null when it went through.
  Object? get lastError => _lastError;

  /// The presence this client publishes for its own member row.
  UserPresence get userPresence => UserPresence(
    status: presence.status,
    clientStatus: {ClientPlatform.desktop: presence.status},
    activities: presence.activities,
  );

  /// Attaches to the active transport, if it changed.
  void reconcile() {
    final service = _serviceProvider();
    if (_bound && identical(service, _service)) return;
    _bound = true;
    unawaited(_updates?.cancel());
    _service = service;
    _lastError = null;
    _updates = service?.selfPresenceUpdates.listen(_accept);
    if (!_disposed) notifyListeners();
  }

  Future<void> setStatus(Presence status) =>
      _edit(() async => _service?.setStatus(status));

  Future<void> setCustomStatus({
    String text = '',
    String emojiName = '',
    CustomStatusDuration expiry = CustomStatusDuration.never,
  }) => _edit(
    () async => _service?.setCustomStatus(
      text: text,
      emojiName: emojiName,
      expiry: expiry,
    ),
  );

  /// Records real user input so the idle machine knows somebody is here.
  void markActive() => _service?.markActive();

  Future<void> _edit(Future<void> Function() write) async {
    if (_service == null) return;
    try {
      await write();
      _lastError = null;
    } on Object catch (error) {
      _lastError = error;
    }
    if (!_disposed) notifyListeners();
  }

  void _accept(SelfPresence presence) {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    _updates = null;
    super.dispose();
  }
}
