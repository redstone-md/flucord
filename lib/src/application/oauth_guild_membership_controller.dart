import 'package:flutter/foundation.dart';

import '../domain/discord_oauth.dart';

enum OAuthGuildMembershipLoadState { idle, loading, ready, failure }

final class OAuthGuildMembershipSnapshot {
  const OAuthGuildMembershipSnapshot._({
    required this.state,
    this.membership,
    this.errorMessage,
  });

  static const idle = OAuthGuildMembershipSnapshot._(
    state: OAuthGuildMembershipLoadState.idle,
  );

  static OAuthGuildMembershipSnapshot loading(
    DiscordOAuthGuildMembership? retained,
  ) => OAuthGuildMembershipSnapshot._(
    state: OAuthGuildMembershipLoadState.loading,
    membership: retained,
  );

  static OAuthGuildMembershipSnapshot ready(
    DiscordOAuthGuildMembership membership,
  ) => OAuthGuildMembershipSnapshot._(
    state: OAuthGuildMembershipLoadState.ready,
    membership: membership,
  );

  static OAuthGuildMembershipSnapshot failure(String message) =>
      OAuthGuildMembershipSnapshot._(
        state: OAuthGuildMembershipLoadState.failure,
        errorMessage: message,
      );

  final OAuthGuildMembershipLoadState state;
  final DiscordOAuthGuildMembership? membership;
  final String? errorMessage;
}

final class OAuthGuildMembershipController extends ChangeNotifier {
  OAuthGuildMembershipController(this._gateway);

  final DiscordOAuthAccountGateway _gateway;
  final Map<String, OAuthGuildMembershipSnapshot> _snapshots = {};

  String? _accountId;
  int _generation = 0;
  bool _disposed = false;

  OAuthGuildMembershipSnapshot snapshotFor(String guildId) =>
      _snapshots[guildId] ?? OAuthGuildMembershipSnapshot.idle;

  void reconcileAccount(String? accountId) {
    if (_accountId == accountId) return;
    _accountId = accountId;
    _generation++;
    final hadSnapshots = _snapshots.isNotEmpty;
    _snapshots.clear();
    if (hadSnapshots && !_disposed) notifyListeners();
  }

  Future<void> load(String guildId, {bool force = false}) async {
    if (_disposed || _accountId == null) return;
    final current = snapshotFor(guildId);
    if (!force &&
        (current.state == OAuthGuildMembershipLoadState.loading ||
            current.state == OAuthGuildMembershipLoadState.ready)) {
      return;
    }
    final generation = _generation;
    _snapshots[guildId] = OAuthGuildMembershipSnapshot.loading(
      current.membership,
    );
    notifyListeners();
    try {
      final membership = await _gateway.fetchCurrentGuildMembership(guildId);
      if (!_accepts(generation)) return;
      _snapshots[guildId] = OAuthGuildMembershipSnapshot.ready(membership);
    } on Object catch (error) {
      if (!_accepts(generation)) return;
      _snapshots[guildId] = OAuthGuildMembershipSnapshot.failure(
        error is DiscordOAuthException
            ? error.message
            : 'Server membership details could not be loaded.',
      );
    }
    notifyListeners();
  }

  Future<void> retry(String guildId) => load(guildId, force: true);

  bool _accepts(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _snapshots.clear();
    super.dispose();
  }
}
