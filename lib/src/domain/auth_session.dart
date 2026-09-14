/// One signed-in session on the account.
///
/// Discord identifies these by a hash rather than by the session id itself, so
/// nothing here can be turned back into a token. The hash is all a client
/// needs: it names a row to end.
final class AuthSession {
  const AuthSession({
    required this.idHash,
    this.platform = '',
    this.os = '',
    this.location = '',
    this.ipAddress = '',
    this.lastUsedAt,
    this.isCurrent = false,
  });

  final String idHash;

  /// The client that signed in — Discord Client, Discord Android, a browser.
  final String platform;

  final String os;

  /// Roughly where Discord placed it, in Discord's words. Empty when Discord
  /// could not place it, which it says rather than guessing.
  final String location;

  /// The address Discord saw. Shown because Discord shows it: it is how
  /// somebody recognises a session that is not theirs.
  final String ipAddress;

  /// Approximate: Discord rounds this deliberately, so it is never presented
  /// as an exact time.
  final DateTime? lastUsedAt;

  /// This session. It is offered no end-this-session control, because ending
  /// it is signing out, which lives elsewhere.
  final bool isCurrent;

  /// One line naming the device, falling back through what Discord sent.
  String get deviceLabel {
    if (platform.isNotEmpty && os.isNotEmpty) return '$platform on $os';
    if (platform.isNotEmpty) return platform;
    if (os.isNotEmpty) return os;
    return 'Unknown device';
  }

  @override
  bool operator ==(Object other) =>
      other is AuthSession &&
      other.idHash == idHash &&
      other.platform == platform &&
      other.os == os &&
      other.location == location &&
      other.ipAddress == ipAddress &&
      other.lastUsedAt == lastUsedAt &&
      other.isCurrent == isCurrent;

  @override
  int get hashCode => Object.hash(
    idHash,
    platform,
    os,
    location,
    ipAddress,
    lastUsedAt,
    isCurrent,
  );
}

/// Reads the account's sessions and ends them.
abstract interface class AuthSessionRepository {
  /// `GET /auth/sessions`, most recently used first.
  Future<List<AuthSession>> loadSessions();

  /// Ends the named sessions.
  ///
  /// Takes a list because Discord's route does: ending five sessions is one
  /// request, and five requests would leave the account half signed out if the
  /// third failed.
  Future<bool> endSessions(List<String> idHashes);
}
