import 'package:flutter/foundation.dart';

import '../domain/account_entitlements.dart';

/// Drives the entitlements page.
///
/// Read-only, because the entitlements are Discord's record of what the
/// account holds: nothing on this page can change them, and offering a
/// control that could not save would be offering a button that lies.
final class AccountEntitlementsController extends ChangeNotifier {
  AccountEntitlementsController(this._repositoryProvider);

  /// Read on every use: the entitlements belong to whichever transport is
  /// signed in, and that is replaced when the account changes.
  final AccountEntitlementsRepository? Function() _repositoryProvider;

  AccountEntitlements? _entitlements;
  Object? _error;
  bool _loading = false;
  bool _disposed = false;

  bool get isAvailable => _repositoryProvider() != null;
  AccountEntitlements? get entitlements => _entitlements;
  Object? get error => _error;
  bool get isLoading => _loading;

  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    if (_entitlements != null && !refresh) return;
    final repository = _repositoryProvider();
    if (repository == null) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      _entitlements = await repository.loadEntitlements();
    } on Object catch (error) {
      _error = error;
    } finally {
      _loading = false;
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
