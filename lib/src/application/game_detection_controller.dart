import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/chat_models.dart';
import '../domain/game_detection.dart';
import '../domain/presence_repository.dart';

/// What a round of detection reads from, before the mapping runs.
///
/// The scanner and the detectable list are the two facts a transport can
/// supply; stating them as a pair is what lets a test drive the controller
/// without a real process walk or a real REST call.
abstract interface class GameDetectionSource {
  /// The basenames of the executables running right now.
  Future<Set<String>> runningExecutables();

  /// The games Discord can recognise, or null when the list cannot be read.
  Future<List<DetectableGame>?> detectableGames();
}

/// Publishes the game being played as the account's own presence.
///
/// Each round reads the source, maps the two facts into an activity with the
/// domain's own rule, and publishes it through the presence contract's
/// local-activity write, which is the same path a custom status and the idle
/// machine already share. Nothing runs while the transport has no presence
/// plane: there is nothing to publish into.
final class GameDetectionController extends ChangeNotifier {
  GameDetectionController({
    required PresenceService? Function() presenceProvider,
    required GameDetectionSource Function() sourceProvider,
    required bool Function() showsCurrentGame,
    this.scanInterval = defaultScanInterval,
    Timer Function(Duration, void Function(Timer))? timerFactory,
  }) : _presenceProvider = presenceProvider,
       _sourceProvider = sourceProvider,
       _showsCurrentGame = showsCurrentGame,
       _timerFactory = timerFactory ?? Timer.periodic;

  /// The cadence a running game is looked for at.
  static const Duration defaultScanInterval = Duration(seconds: 15);

  final PresenceService? Function() _presenceProvider;
  final GameDetectionSource Function() _sourceProvider;
  final bool Function() _showsCurrentGame;
  final Duration scanInterval;
  final Timer Function(Duration, void Function(Timer)) _timerFactory;

  PresenceService? _presence;
  GameDetectionSource? _source;
  Timer? _timer;
  UserActivity? _activity;
  Object? _error;
  bool _detecting = false;
  bool _disposed = false;

  /// Whether the active transport has a presence plane to publish into.
  bool get isAvailable => _presence != null;

  /// The activity the last round published, or null when nothing is running
  /// or the account is not sharing games.
  UserActivity? get activity => _activity;

  /// Why the last round failed, or null when it went through.
  Object? get error => _error;

  /// Attaches to the active transport, if it changed. The activity is not
  /// carried across a session switch: the new transport starts clean.
  void reconcile() {
    if (_disposed) return;
    final presence = _presenceProvider();
    final source = _sourceProvider();
    if (identical(presence, _presence) && identical(source, _source)) return;
    _presence = presence;
    _source = source;
    _activity = null;
    _error = null;
    notifyListeners();
  }

  /// Runs one round and publishes what it found.
  ///
  /// Rounds do not overlap: a scan that finishes after the next one started
  /// is not stale, because each round publishes the whole picture.
  Future<void> detect() async {
    if (_disposed || _detecting) return;
    final presence = _presence;
    final source = _source;
    if (presence == null || source == null) return;
    _detecting = true;
    try {
      final sharing = _showsCurrentGame();
      final running = sharing
          ? await source.runningExecutables()
          : const <String>{};
      final detectable = sharing
          ? await source.detectableGames()
          : const <DetectableGame>[];
      final activities = detectGames(running, detectable ?? const []);
      if (!sharing && activities.isNotEmpty) {
        // The mapping never answers for an empty scan; the guard is for a
        // reader of the invariant, not the wire.
        throw StateError('Detection answered with the sharing gate off');
      }
      await presence.setLocalActivities(activities);
      final next = activities.isEmpty ? null : activities.first;
      _error = null;
      if (next != _activity) {
        _activity = next;
        notifyListeners();
      }
    } on Object catch (error) {
      _error = error;
      notifyListeners();
    } finally {
      _detecting = false;
    }
  }

  /// Starts the periodic scan. Safe to call again; the second is a no-op.
  void startScanning() {
    if (_timer != null || _disposed) return;
    _timer = _timerFactory(scanInterval, (timer) {
      // A timer stopped after its callback was queued must not fire: the
      // cadence is the timer's own, so a stopped scan rounds nothing.
      if (!timer.isActive) return;
      unawaited(detect());
    });
    unawaited(detect());
  }

  /// Stops the periodic scan. What is already published stays published.
  void stopScanning() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stopScanning();
    super.dispose();
  }
}
