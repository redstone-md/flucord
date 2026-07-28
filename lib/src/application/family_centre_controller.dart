import 'package:flutter/foundation.dart';

import '../domain/family_centre.dart';

/// Drives the family-centre page.
///
/// Loads once when the page is opened. The link code is asked for only when
/// somebody asks: it is a credential a parent types, and minting one on page
/// load would put a live code on screen nobody wanted.
final class FamilyCentreController extends ChangeNotifier {
  FamilyCentreController(this._repositoryProvider);

  /// Read on every use: the family centre belongs to whichever transport is
  /// signed in, and that is replaced when the account changes.
  final FamilyCentreRepository? Function() _repositoryProvider;

  FamilyCentre? _familyCentre;
  Object? _error;
  String? _linkCode;
  bool _loading = false;
  bool _requestingCode = false;
  bool _linkCodeRefused = false;
  bool _disposed = false;

  bool get isAvailable => _repositoryProvider() != null;
  FamilyCentre? get familyCentre => _familyCentre;
  Object? get error => _error;
  bool get isLoading => _loading;
  bool get isRequestingLinkCode => _requestingCode;

  /// The code a parent types, once one has been asked for.
  String? get linkCode => _linkCode;

  /// Discord declined to issue one. Not an error: an account that is not
  /// eligible gets this, and it is an answer.
  bool get wasLinkCodeRefused => _linkCodeRefused;

  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    if (_familyCentre != null && !refresh) return;
    final repository = _repositoryProvider();
    if (repository == null) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      _familyCentre = await repository.loadFamilyCentre();
    } on Object catch (error) {
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Asks Discord for the code that links a parent to this account.
  Future<String?> requestLinkCode() async {
    if (_requestingCode) return _linkCode;
    final repository = _repositoryProvider();
    if (repository == null) return null;
    _requestingCode = true;
    _linkCodeRefused = false;
    _notify();
    try {
      final code = await repository.requestLinkCode();
      _linkCode = code;
      _linkCodeRefused = code == null;
      return code;
    } on Object catch (error) {
      _error = error;
      return null;
    } finally {
      _requestingCode = false;
      _notify();
    }
  }

  /// Drops the code from memory once it has been used or the page closed.
  ///
  /// A link code grants a parent a view of this account, so it is not left
  /// sitting on a screen for the next person who opens settings.
  void forgetLinkCode() {
    if (_linkCode == null && !_linkCodeRefused) return;
    _linkCode = null;
    _linkCodeRefused = false;
    _notify();
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
