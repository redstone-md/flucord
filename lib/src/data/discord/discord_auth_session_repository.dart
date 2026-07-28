import '../../domain/auth_session.dart';
import 'discord_rest_client.dart';

/// The account's signed-in sessions, over the desktop-user session.
///
/// Ending a session requires the account password on Discord's own client for
/// some accounts; this sends the request and reports the refusal rather than
/// asking for a password it has nowhere to put.
final class DiscordAuthSessionRepository implements AuthSessionRepository {
  DiscordAuthSessionRepository(this._rest);

  final DiscordRestClient _rest;

  @override
  Future<List<AuthSession>> loadSessions() async =>
      readSessions(await _rest.getObject('/auth/sessions'));

  @override
  Future<bool> endSessions(List<String> idHashes) async {
    final named = [
      for (final hash in idHashes)
        if (hash.isNotEmpty) hash,
    ];
    if (named.isEmpty) return false;
    try {
      await _rest.requestEmpty(
        'POST',
        '/auth/sessions/logout',
        body: {'session_id_hashes': named},
      );
      return true;
    } on DiscordApiException catch (error) {
      // Discord asks some accounts to re-enter their password before it will
      // end a session. That is a refusal to act, not a transport failure, and
      // the surface says so rather than showing a crash.
      if (error.statusCode == 400 || error.statusCode == 401) return false;
      rethrow;
    }
  }

  /// Reads the session list.
  ///
  /// The payload wraps the list in `user_sessions` on the desktop route; a
  /// bare list is accepted too, because the same shape is served either way
  /// depending on the build.
  static List<AuthSession> readSessions(Object? payload) {
    final entries = switch (payload) {
      final List raw => raw,
      final Map raw => _list(raw['user_sessions']),
      _ => const [],
    };
    return [for (final raw in entries) ?_session(raw)];
  }

  static AuthSession? _session(Object? raw) {
    if (raw is! Map) return null;
    final payload = raw.cast<String, Object?>();
    final idHash = _string(payload['id_hash']);
    if (idHash == null) return null;
    final client = payload['client_info'] is Map
        ? (payload['client_info']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return AuthSession(
      idHash: idHash,
      platform: _string(client['platform']) ?? '',
      os: _string(client['os']) ?? '',
      location: _string(client['location']) ?? '',
      ipAddress: _string(client['ip']) ?? '',
      lastUsedAt: _time(payload['approx_last_used_time']),
      // Discord marks the caller's own row; a payload that marks none leaves
      // every row endable, which is what the route would allow anyway.
      isCurrent: payload['is_current'] == true || payload['current'] == true,
    );
  }

  static DateTime? _time(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static String? _string(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }
}
