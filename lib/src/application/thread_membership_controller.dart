import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/thread_membership.dart';

/// Drives the join/leave control on a thread.
///
/// The repository is resolved through a provider for the same reason the
/// settings and profile controllers do it: the transport is replaced when the
/// session changes, and a captured one would keep joining threads as an
/// account nobody is signed in as.
final class ThreadMembershipController extends ChangeNotifier {
  ThreadMembershipController(this._repositoryProvider);

  final ThreadMembershipRepository? Function() _repositoryProvider;

  ThreadMembershipRepository? _repository;
  StreamSubscription<ThreadMembership>? _updates;
  bool _bound = false;
  bool _disposed = false;

  String? _threadId;
  bool _isBusy = false;
  bool _isLoading = false;
  Object? _error;

  /// Whether this transport can join threads at all.
  bool get isSupported {
    _bind();
    return _repository != null;
  }

  /// The thread this controller is showing, or `null`.
  String? get threadId => _threadId;

  ThreadMembership? get membership =>
      _threadId == null ? null : _repository?.membershipFor(_threadId!);

  bool get isJoined => membership?.isSelfJoined ?? false;
  int get memberCount => membership?.displayCount ?? 0;
  bool get isBusy => _isBusy;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  /// Points the controller at [threadId], reading its members.
  ///
  /// Passing null — the channel is not a thread — clears the surface rather
  /// than leaving the previous thread's answer on screen.
  void show(String? threadId) {
    _bind();
    if (_threadId == threadId) return;
    _threadId = threadId;
    _error = null;
    _notify();
    if (threadId != null) unawaited(load());
  }

  Future<void> load() async {
    _bind();
    final repository = _repository;
    final threadId = _threadId;
    if (repository == null || threadId == null || _isLoading) return;
    _isLoading = true;
    _error = null;
    _notify();
    try {
      await repository.loadMembers(threadId);
    } on Object catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<bool> join() =>
      _apply((repository, threadId) => repository.joinThread(threadId));

  Future<bool> leave() =>
      _apply((repository, threadId) => repository.leaveThread(threadId));

  /// Joins or leaves, whichever the current membership makes sense.
  Future<bool> toggle() => isJoined ? leave() : join();

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    _updates = null;
    super.dispose();
  }

  Future<bool> _apply(
    Future<void> Function(ThreadMembershipRepository, String) action,
  ) async {
    final repository = _repository;
    final threadId = _threadId;
    if (repository == null || threadId == null || _isBusy) return false;
    _isBusy = true;
    _error = null;
    _notify();
    try {
      await action(repository, threadId);
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _isBusy = false;
      _notify();
    }
  }

  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    unawaited(_updates?.cancel());
    _repository = repository;
    _updates = repository?.updates.listen(_accept);
    return true;
  }

  void _accept(ThreadMembership membership) {
    // Only the thread on screen repaints: the store answers for every thread
    // the session has touched, and most of them are not being looked at.
    if (membership.threadId == _threadId) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
