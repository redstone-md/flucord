/// The idle and AFK state opcode 3 reports, as R07's `IdleStore` keeps it.
///
/// Two thresholds, not one. Idle is a fixed ten minutes and is what turns the
/// account's dot yellow; AFK is the account's own `afkTimeout` setting capped
/// at that same ten minutes and is what moves the user out of a voice channel.
/// Collapsing them would either move people out of voice after ten minutes
/// regardless of their setting, or turn the dot yellow after one.
///
/// Nothing here reads a clock or owns a timer: every transition is a call, so
/// the whole machine is exercised without waiting and a platform that learns
/// to see real system input later only has to call [markActive] more often.
final class DiscordIdleTracker {
  DiscordIdleTracker({DateTime? startedAt})
    : _lastInputAtMs = (startedAt ?? DateTime.now()).millisecondsSinceEpoch;

  /// R07's `IDLE_THRESHOLD`, ten minutes.
  static const idleThreshold = Duration(minutes: 10);

  /// How long two [markActive] calls must be apart to both count.
  ///
  /// Pointer movement arrives per frame; without this the tracker would do a
  /// full re-evaluation sixty times a second to learn nothing new.
  static const markThrottle = Duration(milliseconds: 500);

  /// R06's proto default for `voiceAndVideo.afkTimeout`, in seconds.
  static const defaultAfkTimeoutSeconds = 60;

  int _lastInputAtMs;
  int _lastMarkAtMs = 0;
  int? _suspendMarkerMs;
  int _afkTimeoutSeconds = defaultAfkTimeoutSeconds;
  bool _isIdle = false;
  bool _isAfk = false;
  bool _systemSuspended = false;
  bool _systemLocked = false;

  bool get isIdle => _isIdle;
  bool get isAfk => _isAfk;

  /// R07: the timestamp of the *last input*, not the moment idle began, and
  /// null while the user is active. It goes on the wire as `since`.
  int? get idleSince => _isIdle ? _lastInputAtMs : null;

  int get afkTimeoutSeconds => _afkTimeoutSeconds;

  /// Applies the account's `voiceAndVideo.afkTimeout`.
  ///
  /// A negative value is refused rather than clamped: it would otherwise make
  /// `min(timeout, idleThreshold)` negative and mark the account AFK the
  /// instant it connected.
  bool setAfkTimeoutSeconds(int seconds, {required DateTime now}) {
    final next = seconds < 0 ? defaultAfkTimeoutSeconds : seconds;
    if (next == _afkTimeoutSeconds) return false;
    _afkTimeoutSeconds = next;
    return evaluate(now);
  }

  /// Records real user input. Returns whether the idle or AFK answer changed.
  bool markActive(DateTime now) {
    final nowMs = now.millisecondsSinceEpoch;
    if (nowMs - _lastMarkAtMs < markThrottle.inMilliseconds &&
        _lastMarkAtMs > 0) {
      return false;
    }
    _lastMarkAtMs = nowMs;
    if (nowMs > _lastInputAtMs) _lastInputAtMs = nowMs;
    // Input proves the machine is awake and unlocked. Without a power monitor
    // this is the only thing that can retire the marker, and leaving it set
    // would pin the account to AFK for the rest of the session.
    _suspendMarkerMs = null;
    return evaluate(now);
  }

  /// The machine went to sleep or the screen locked.
  bool setBlocked({
    required DateTime now,
    bool? systemSuspended,
    bool? systemLocked,
  }) {
    final wasBlocked = _isBlocked;
    _systemSuspended = systemSuspended ?? _systemSuspended;
    _systemLocked = systemLocked ?? _systemLocked;
    if (!wasBlocked && _isBlocked) {
      _suspendMarkerMs = now.millisecondsSinceEpoch;
    }
    return evaluate(now);
  }

  /// Recomputes both flags. Returns whether either changed.
  bool evaluate(DateTime now) {
    final sinceInput = now.millisecondsSinceEpoch - _lastInputAtMs;
    final blocked = _isBlocked;
    final idle = sinceInput > idleThreshold.inMilliseconds || blocked;
    final afkLimit = _afkTimeoutSeconds * Duration.millisecondsPerSecond;
    final afk =
        _afkTimeoutSeconds == 0 ||
        _suspendMarkerMs != null ||
        sinceInput >
            (afkLimit < idleThreshold.inMilliseconds
                ? afkLimit
                : idleThreshold.inMilliseconds) ||
        blocked;
    if (idle == _isIdle && afk == _isAfk) return false;
    _isIdle = idle;
    _isAfk = afk;
    return true;
  }

  /// R07's `blocked()`. The Android-only "app backgrounded" arm is absent
  /// because this client only runs on desktop, where backgrounding a window is
  /// not the same as the user having gone away.
  bool get _isBlocked => _systemSuspended || _systemLocked;
}
