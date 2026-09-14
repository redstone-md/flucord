/// A member's standing in one guild, reduced to what permissions depend on.
///
/// Kept apart from the display-facing member record because these fields have
/// no visual meaning at all: they exist only to feed the clamps Discord applies
/// after roles and overwrites have been resolved. A member with no record here
/// is not "a member with no roles" — it is a member we were never told about,
/// which callers must decide about themselves.
final class GuildMembership {
  const GuildMembership({
    this.roleIds = const [],
    this.flags = 0,
    this.isPending = false,
    this.timeoutUntil,
  });

  /// Member flag `IS_GUEST`.
  static const guestFlag = 16;

  /// The three automod quarantine flags, OR'd: username/nickname, bio, and
  /// server tag. Discord treats any of them as "quarantined".
  static const quarantinedFlags = 128 | 256 | 1024;

  /// Role ids the member holds. Never includes `@everyone`, which is implied.
  final List<String> roleIds;

  /// The `flags` bitfield from the member payload.
  final int flags;

  /// `pending`: membership screening has not been completed.
  final bool isPending;

  /// `communication_disabled_until`. In the past, or null, means not timed out.
  final DateTime? timeoutUntil;

  bool get isGuest => flags & guestFlag != 0;

  bool get isQuarantined => flags & quarantinedFlags != 0;

  /// Timeouts expire on a wall clock the caller owns, so the moment is passed
  /// in rather than read here — otherwise nothing about a permission result
  /// would be reproducible in a test.
  bool isTimedOutAt(DateTime now) => timeoutUntil?.isAfter(now) ?? false;

  @override
  bool operator ==(Object other) =>
      other is GuildMembership &&
      other.flags == flags &&
      other.isPending == isPending &&
      other.timeoutUntil == timeoutUntil &&
      _sameRoles(other.roleIds);

  bool _sameRoles(List<String> other) {
    if (other.length != roleIds.length) return false;
    for (var index = 0; index < roleIds.length; index++) {
      if (other[index] != roleIds[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(roleIds), flags, isPending, timeoutUntil);
}
