part of 'chat_controller.dart';

/// Who moved in the last presence fold. The chat controller does not notify
/// its own listeners for presence, so the shell does not rebuild for it; the
/// widgets that show a person listen here instead, through `PresenceScope`.
final class PresenceChanges extends ChangeNotifier {
  Set<String> _moved = const {};
  Set<String> _flipped = const {};

  /// The people whose presence changed in the last fold.
  Set<String> get moved => _moved;

  /// The people among [moved] who went online or offline.
  Set<String> get flipped => _flipped;

  void _announce(ChatWorkspace before, ChatWorkspace after, Set<String> ids) {
    _moved = ids;
    _flipped = {
      for (final id in ids)
        if (before.memberOrNull(id)?.presence.isOnline !=
            after.memberOrNull(id)?.presence.isOnline)
          id,
    };
    notifyListeners();
  }
}

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
    final after = before?.applyPresences(_heldPresences);
    final moved = {
      if (before != null && after != null && !identical(before, after))
        for (final id in _heldPresences.keys)
          if (!identical(before.memberOrNull(id), after.memberOrNull(id))) id,
    };
    _heldPresences.clear();
    _workspace = after;
    if (moved.isNotEmpty) presenceChanges._announce(before!, after!, moved);
  }
}
