import 'package:flutter/foundation.dart';

import '../domain/account_standing.dart';

/// Drives the account-standing page.
///
/// Loads once when the page is opened and not again unless asked. Nothing here
/// polls: a record changes when Discord decides it does, which is not
/// something a client can watch for, and re-reading on every rebuild would
/// spend a rate limit to show the same answer.
final class AccountStandingController extends ChangeNotifier {
  AccountStandingController(this._repositoryProvider);

  /// Read on every use rather than held: the safety hub belongs to whichever
  /// transport is signed in, and that is replaced when the account changes.
  final SafetyHubRepository? Function() _repositoryProvider;

  /// Whether there is a transport behind this at all.
  bool get isAvailable => _repositoryProvider() != null;

  AccountStanding? _standing;
  Object? _error;
  bool _loading = false;
  bool _disposed = false;
  final Set<String> _requested = {};
  final Set<String> _refused = {};

  AccountStanding? get standing => _standing;
  Object? get error => _error;
  bool get isLoading => _loading;

  /// Records a review has been asked for. Kept per id so the button can say
  /// so rather than inviting the same request again.
  bool hasRequestedReview(String classificationId) =>
      _requested.contains(classificationId);

  /// Records Discord declined to look at again. Not an error: an account that
  /// already appealed gets this, and it is an answer, not a failure.
  bool wasReviewRefused(String classificationId) =>
      _refused.contains(classificationId);

  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    if (_standing != null && !refresh) return;
    final repository = _repositoryProvider();
    if (repository == null) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      _standing = await repository.loadAccountStanding();
    } on Object catch (error) {
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Asks Discord to look at one record again.
  Future<bool> requestReview(String classificationId) async {
    if (classificationId.isEmpty) return false;
    if (_requested.contains(classificationId)) return false;
    final repository = _repositoryProvider();
    if (repository == null) return false;
    try {
      final accepted = await repository.requestReview(classificationId);
      if (accepted) {
        _requested.add(classificationId);
      } else {
        _refused.add(classificationId);
      }
      _notify();
      return accepted;
    } on Object catch (error) {
      _error = error;
      _notify();
      return false;
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
