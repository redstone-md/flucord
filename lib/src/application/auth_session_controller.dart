import 'package:flutter/foundation.dart';

import '../domain/auth_session.dart';

/// Drives the devices page.
///
/// Ending a session is the one destructive thing user settings can do to
/// another device, so it is never batched with anything else and the list is
/// re-read afterwards rather than patched: the answer says the request was
/// accepted, not which rows survived it.
final class AuthSessionController extends ChangeNotifier {
  AuthSessionController(this._repositoryProvider);

  final AuthSessionRepository? Function() _repositoryProvider;

  List<AuthSession> _sessions = const [];
  Object? _error;
  bool _loading = false;
  bool _ending = false;
  bool _endRefused = false;
  bool _disposed = false;

  bool get isAvailable => _repositoryProvider() != null;
  List<AuthSession> get sessions => List.unmodifiable(_sessions);
  Object? get error => _error;
  bool get isLoading => _loading;
  bool get isEnding => _ending;

  /// Discord declined to end a session, which it does when it wants the
  /// account password first. An answer, not a fault.
  bool get wasEndRefused => _endRefused;

  /// Every session but this one. What "sign out everywhere else" acts on.
  List<AuthSession> get otherSessions => [
    for (final session in _sessions)
      if (!session.isCurrent) session,
  ];

  bool _loaded = false;

  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    if (_loaded && !refresh) return;
    final repository = _repositoryProvider();
    if (repository == null) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      _sessions = await repository.loadSessions();
      _loaded = true;
    } on Object catch (error) {
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<bool> endSession(String idHash) => _end([idHash]);

  /// Ends every session but this one, in a single request.
  Future<bool> endOtherSessions() =>
      _end([for (final session in otherSessions) session.idHash]);

  Future<bool> _end(List<String> idHashes) async {
    if (_ending || idHashes.isEmpty) return false;
    final repository = _repositoryProvider();
    if (repository == null) return false;
    _ending = true;
    _endRefused = false;
    _error = null;
    _notify();
    try {
      final accepted = await repository.endSessions(idHashes);
      _endRefused = !accepted;
      if (accepted) {
        // Re-read rather than remove the rows: the route answers that it was
        // accepted, not which sessions it actually ended.
        _sessions = await repository.loadSessions();
      }
      return accepted;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _ending = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
