import 'package:flutter/foundation.dart';

import '../domain/age_verification.dart';
import '../domain/external_link_launcher.dart';

/// Drives the age-verification page.
///
/// Starting a method hands off to the vendor that carries it out. Nothing
/// about the person — no document, no photograph, no wallet credential —
/// passes through this controller, because none of it passes through Flucord
/// at all.
final class AgeVerificationController extends ChangeNotifier {
  AgeVerificationController(
    this._repositoryProvider, {
    required ExternalLinkLauncher launcher,
  }) : _launcher = launcher;

  final AgeVerificationRepository? Function() _repositoryProvider;
  final ExternalLinkLauncher _launcher;

  List<AgeVerificationMethod> _methods = const [];
  Object? _error;
  bool _loading = false;
  bool _starting = false;
  bool _loaded = false;
  AgeVerificationMethod? _refused;
  AgeVerificationMethod? _needsVendorSurface;
  bool _disposed = false;

  bool get isAvailable => _repositoryProvider() != null;
  List<AgeVerificationMethod> get methods => List.unmodifiable(_methods);
  bool get isLoading => _loading;
  bool get isStarting => _starting;
  Object? get error => _error;

  /// The method Discord would not start for this account. An answer about
  /// eligibility rather than a fault.
  AgeVerificationMethod? get refusedMethod => _refused;

  /// The method Discord started but which continues on a vendor surface this
  /// build does not carry. Stated rather than hidden: the person is otherwise
  /// left tapping a button that appears to do nothing.
  AgeVerificationMethod? get methodNeedingVendorSurface => _needsVendorSurface;

  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    if (_loaded && !refresh) return;
    final repository = _repositoryProvider();
    if (repository == null) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      _methods = await repository.loadMethods();
      _loaded = true;
    } on Object catch (error) {
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Starts [method] and opens where Discord says it continues.
  Future<bool> start(AgeVerificationMethod method) async {
    final repository = _repositoryProvider();
    if (repository == null || _starting) return false;
    _starting = true;
    _refused = null;
    _needsVendorSurface = null;
    _error = null;
    _notify();
    try {
      final started = await repository.start(method);
      if (started == null) {
        _refused = method;
        return false;
      }
      if (!started.canContinue) {
        _needsVendorSurface = method;
        return false;
      }
      // Opened outside: the check belongs to the vendor, and putting their
      // page in a window of ours would be putting Flucord between somebody
      // and their identity document.
      return _launcher.open(Uri.parse(started.continueUrl));
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _starting = false;
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
