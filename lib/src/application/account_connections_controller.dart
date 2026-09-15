import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/account_connections.dart';
import '../domain/external_link_launcher.dart';

/// Drives the connections settings page.
///
/// Linking opens the service's own page outside the app: the exchange of
/// credentials belongs to the person and the service, and none of it passes
/// through Flucord. The list is re-read after a link is started because the
/// service's page, not this client, is where the link completes, and the
/// next visit to the page is when the result should be looked for.
final class AccountConnectionsController extends ChangeNotifier {
  AccountConnectionsController(
    this._repositoryProvider, {
    required ExternalLinkLauncher launcher,
  }) : _launcher = launcher;

  /// Read on every use: the connections belong to whichever transport is
  /// signed in, and that is replaced when the account changes.
  final AccountConnectionsRepository? Function() _repositoryProvider;
  final ExternalLinkLauncher _launcher;

  List<AccountConnection> _connections = const [];
  Object? _error;
  String? _refusedType;
  bool _loading = false;
  bool _linking = false;
  bool _unlinking = false;
  String? _unlinkRefusal;
  bool _disposed = false;

  bool get isAvailable => _repositoryProvider() != null;
  List<AccountConnection> get connections => List.unmodifiable(_connections);
  bool get isLoading => _loading;
  bool get isLinking => _linking;
  bool get isUnlinking => _unlinking;
  Object? get error => _error;

  /// The service Discord will not let this account link, named so the page
  /// can say which one was refused rather than reading it as an outage.
  String? get refusedService => _refusedType;

  /// The unlink Discord refused, named the same way.
  String? get unlinkRefusal => _unlinkRefusal;

  /// Loads the list once when the page is opened, and again only when asked.
  Future<void> load({bool refresh = false}) async {
    if (_loading) return;
    if (_connections.isNotEmpty && !refresh) return;
    final repository = _repositoryProvider();
    if (repository == null) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      _connections = await repository.loadConnections();
    } on Object catch (error) {
      _error = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Starts a link by opening where the service's own page begins.
  ///
  /// Returns false when the link could not be started, which is an answer
  /// about the service rather than a fault: the page says which.
  Future<bool> startLink(String type) async {
    final repository = _repositoryProvider();
    final normalized = type.trim();
    if (repository == null || _linking || normalized.isEmpty) return false;
    _linking = true;
    _refusedType = null;
    _error = null;
    _notify();
    try {
      final url = await repository.startLink(normalized);
      if (url == null) {
        _refusedType = normalized;
        return false;
      }
      // Opened outside: the link is the service's to finish, and putting
      // their sign-in page in a window of ours would be putting Flucord
      // between somebody and the credentials to their other account.
      return _launcher.open(Uri.parse(url));
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _linking = false;
      _notify();
    }
  }

  /// Removes a link.
  ///
  /// Returns false when Discord refused, and says which link was refused so
  /// the page can name it rather than read the refusal as an outage.
  Future<bool> unlink(AccountConnection connection) async {
    final repository = _repositoryProvider();
    if (repository == null || _unlinking) return false;
    _unlinking = true;
    _unlinkRefusal = null;
    _error = null;
    _notify();
    try {
      await repository.unlink(connection);
      _connections = [
        for (final other in _connections)
          if (other != connection) other,
      ];
      return true;
    } on AccountConnectionException {
      _unlinkRefusal = connection.serviceName;
      return false;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _unlinking = false;
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
