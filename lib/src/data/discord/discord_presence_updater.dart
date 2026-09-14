import 'dart:async';
import 'dart:convert';

import '../../domain/chat_models.dart';
import 'discord_self_presence.dart';

/// How the updater schedules a deferred send. Injected so the sliding window
/// can be exercised without a real twenty-second wait.
typedef DiscordPresenceTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// Emits opcode 3, no more often than Discord accepts it.
///
/// Two rules are doing the work. The dirty check stops a presence identical to
/// the one already sent from going out at all — the settings store republishes
/// the whole blob for an unrelated edit, and without it every theme change
/// would cost a presence frame. The sliding window then caps what survives
/// that at five frames per twenty seconds, deferring rather than dropping, so
/// a burst of status changes still ends with the state the user last chose.
final class DiscordPresenceUpdater {
  DiscordPresenceUpdater({
    required this._send,
    required this._isSessionEstablished,
    DateTime Function()? clock,
    DiscordPresenceTimerFactory? timerFactory,
  }) : _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new;

  /// R07: at most five frames per rolling window.
  static const windowLimit = 5;

  /// R07: the window each send occupies.
  static const window = Duration(seconds: 20);

  final void Function(Map<String, Object?> payload) _send;
  final bool Function() _isSessionEstablished;
  final DateTime Function() _clock;
  final DiscordPresenceTimerFactory _timerFactory;

  /// Expiry stamps of the sends still inside the window.
  final List<int> _windowExpiries = [];

  SelfPresence? _desired;
  String? _committedSignature;
  Map<String, Object?>? _deferredPayload;
  Timer? _deferredTimer;

  /// The last payload handed to the socket, for the IDENTIFY that follows a
  /// reconnect. R07: the two carry the same object, so re-identifying with the
  /// last committed presence is what stops a fresh session from silently
  /// reverting the account to online.
  Map<String, Object?>? get lastPayload => _lastPayload;
  Map<String, Object?>? _lastPayload;

  SelfPresence? get desired => _desired;

  /// Records the presence this client wants and sends it if it is new.
  void update(SelfPresence next) {
    _desired = next;
    _commitIfDirty();
  }

  /// The gateway session came up; anything held back can go now.
  void sessionEstablished() => _commitIfDirty();

  /// Gateway `RESUMED`. R07: a resume always re-asserts presence, because the
  /// server may have dropped what the previous socket told it.
  void forceUpdate() {
    final desired = _desired;
    if (desired == null || !_isSessionEstablished()) return;
    _committedSignature = null;
    _commitIfDirty();
  }

  /// Forgets what was sent, for a new session or a switched account.
  void reset() {
    _committedSignature = null;
    _lastPayload = null;
    _deferredPayload = null;
    _deferredTimer?.cancel();
    _deferredTimer = null;
    _windowExpiries.clear();
  }

  void dispose() {
    _deferredTimer?.cancel();
    _deferredTimer = null;
  }

  void _commitIfDirty() {
    final desired = _desired;
    if (desired == null || !_isSessionEstablished()) return;
    final payload = DiscordSelfPresence.toWire(desired);
    final signature = jsonEncode(payload);
    if (signature == _committedSignature) return;
    _committedSignature = signature;
    _emit(payload);
  }

  /// R07's limiter, verbatim: drop expired slots, send while a slot is free,
  /// otherwise wait for the oldest to expire and send whatever is newest then.
  void _emit(Map<String, Object?> payload) {
    final nowMs = _clock().millisecondsSinceEpoch;
    _deferredTimer?.cancel();
    _deferredTimer = null;
    _windowExpiries.removeWhere((expiry) => expiry <= nowMs);
    if (_windowExpiries.length < windowLimit) {
      _windowExpiries.add(nowMs + window.inMilliseconds);
      _deferredPayload = null;
      _lastPayload = payload;
      _send(payload);
      return;
    }
    _deferredPayload = payload;
    _deferredTimer = _timerFactory(
      Duration(milliseconds: _windowExpiries.first - nowMs),
      _flushDeferred,
    );
  }

  void _flushDeferred() {
    _deferredTimer = null;
    final payload = _deferredPayload;
    if (payload == null) return;
    _emit(payload);
  }
}
