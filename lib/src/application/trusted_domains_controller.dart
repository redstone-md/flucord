import 'package:flutter/foundation.dart';

import '../domain/trusted_domains.dart';

/// The hosts a link from a message opens on without the "Leaving" dialog.
///
/// A change applies first and is saved after, so the next click answers
/// at once. A write that fails keeps the change for this run and leaves the
/// failure where the settings window can show it.
final class TrustedDomainsController extends ChangeNotifier {
  TrustedDomainsController(this._repository);

  final TrustedDomainsRepository _repository;

  TrustedDomains _domains = TrustedDomains.none;
  bool _loaded = false;
  Object? _writeError;
  bool _disposed = false;

  /// The hosts the person trusted, in lower case.
  Set<String> get hosts => _domains.hosts;

  /// The last failed write, cleared by the next successful one.
  Object? get writeError => _writeError;

  bool trusts(Uri uri) => _domains.trusts(uri);

  Future<void> load() async {
    if (_loaded) return;
    _domains = await _repository.load();
    _loaded = true;
    _notify();
  }

  /// Trusts the host of [uri] from now on.
  Future<void> trust(Uri uri) => _persist(_domains.adding(uri));

  /// Forgets every trusted host, so each asks again.
  Future<void> clear() => _persist(TrustedDomains.none);

  Future<void> _persist(TrustedDomains domains) async {
    _domains = domains;
    _notify();
    try {
      await _repository.save(_domains);
      _writeError = null;
    } catch (error) {
      _writeError = error;
    }
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
