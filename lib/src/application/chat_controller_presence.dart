part of 'chat_controller.dart';

/// Holds incoming presences for a moment, so a burst folds into the workspace
/// once. The whole member table is copied per fold, and Discord can send
/// hundreds of presences a second on a big account.
extension _ChatControllerPresence on ChatController {
  /// Counted from the first presence of a batch, and not moved by later ones,
  /// so a steady stream still reaches the screen.
  static const _window = Duration(milliseconds: 150);

  void _holdPresences(Map<String, UserPresence> presences) {
    _heldPresences.addAll(presences);
    _presenceFold ??= Timer(_window, _foldHeldPresences);
  }

  void _foldHeldPresences() {
    _presenceFold = null;
    final before = _workspace;
    _workspace = before?.applyPresences(_heldPresences);
    _heldPresences.clear();
    if (!identical(_workspace, before)) _notify();
  }
}
