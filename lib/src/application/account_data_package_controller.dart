import 'package:flutter/foundation.dart';

import '../domain/account_data_package.dart';

/// Drives the data-package page.
///
/// The request starts a collection on Discord's side and the archive arrives
/// by email, so this page's whole job is to start it and to say where it
/// stands. Nothing is downloaded here and no link is opened by the client.
final class AccountDataPackageController extends ChangeNotifier {
  AccountDataPackageController(this._repositoryProvider);

  /// Read on every use: the data belongs to whichever transport is signed
  /// in, and that is replaced when the account changes.
  final AccountDataPackageRepository? Function() _repositoryProvider;

  AccountDataPackage? _package;
  Object? _error;
  bool _loading = false;
  bool _loaded = false;
  bool _requesting = false;
  bool _refused = false;
  bool _disposed = false;

  bool get isAvailable => _repositoryProvider() != null;
  AccountDataPackage? get package => _package;
  bool get isLoading => _loading;
  bool get isRequesting => _requesting;
  Object? get error => _error;

  /// The last request Discord would not start, which is an answer about the
  /// account rather than a fault in the client.
  bool get wasRefused => _refused;

  /// Loads where the request stands, once when the page opens and again only
  /// when asked.
  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    // A read that found no request is still a read: it is only asked again
    // when asked for, not on every build.
    if (_loaded && !refresh) return;
    final repository = _repositoryProvider();
    if (repository == null) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      _package = await repository.loadLatest();
      _loaded = true;
    } on Object catch (error) {
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Starts a request.
  ///
  /// Returns false when Discord refused, which it does for an account with
  /// no verified email address or one whose earlier request has not
  /// finished. Both are answers the page states rather than faults.
  Future<bool> request() async {
    final repository = _repositoryProvider();
    if (repository == null || _requesting) return false;
    _requesting = true;
    _refused = false;
    _error = null;
    _notify();
    try {
      final package = await repository.request();
      if (package == null) {
        _refused = true;
        return false;
      }
      _package = package;
      return true;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _requesting = false;
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
