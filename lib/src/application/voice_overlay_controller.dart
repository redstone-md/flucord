import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/voice_overlay.dart';

/// Who the overlay should be showing, as the room sees it.
typedef OverlayRoster = List<OverlaySpeaker> Function();

/// The in-game overlay: on, off, and what it says.
///
/// Kept apart from the room widget because it outlives it — the point of an
/// overlay is that it is on screen while Flucord is not — so what it draws
/// comes from a provider read on demand rather than from a build.
final class VoiceOverlayController extends ChangeNotifier {
  VoiceOverlayController({
    required VoiceOverlay overlay,
    required OverlayRoster roster,
    required bool Function() isHiddenByStreamerMode,
  }) : _overlay = overlay,
       _roster = roster,
       _isHidden = isHiddenByStreamerMode;

  final VoiceOverlay _overlay;
  final OverlayRoster _roster;
  final bool Function() _isHidden;

  bool _wanted = false;
  bool _disposed = false;

  bool get isSupported => _overlay.isSupported;

  /// Whether somebody asked for it, which is not the same as it being drawn:
  /// streamer mode hides it without turning it off.
  bool get isWanted => _wanted;

  bool get isVisible => _overlay.isVisible;

  Future<void> setEnabled({required bool enabled}) async {
    if (_wanted == enabled) return;
    _wanted = enabled;
    await refresh();
    _notify();
  }

  Future<void> toggle() => setEnabled(enabled: !_wanted);

  /// Redraws, or takes it off screen when it should not be there.
  ///
  /// Called whenever the roster or streamer mode changes: an overlay showing
  /// who was in the room a minute ago is worse than none.
  Future<void> refresh() async {
    if (!_wanted || _isHidden()) {
      _overlay.hide();
      return;
    }
    await _overlay.show(_roster());
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _overlay.close();
    super.dispose();
  }
}
