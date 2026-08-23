import 'dart:async';
import 'dart:collection';

import 'discord_desktop_rest_protocol.dart';
import 'discord_rest_client.dart';
import '../../app_log.dart';

/// Sends one built request and hands back the decoded body, if any.
typedef DiscordReadStateAckSender =
    Future<Map<String, Object?>?> Function(DiscordDesktopRestRequest request);

/// One channel acknowledgement waiting for its debounce to elapse.
final class DiscordPendingAck {
  const DiscordPendingAck({
    required this.channelId,
    required this.messageId,
    this.lastViewed,
    this.flags,
  });

  final String channelId;
  final String messageId;
  final int? lastViewed;
  final int? flags;
}

/// The outbound half of read state: debounce, token, retry and the bulk pump.
///
/// Reading a channel produces one acknowledgement per scroll tick, so the wire
/// traffic has to be coalesced before it is sent — R04 measures Discord's own
/// client at a 3 s timer per read state, collapsed to zero when the channel has
/// mentions. The rolling ACK token is the other reason this exists: it is
/// global, single-valued and replaced by each response, so it cannot live on a
/// per-channel record.
final class DiscordReadStateAckQueue {
  DiscordReadStateAckQueue({
    required DiscordReadStateAckSender send,
    DelayFunction? delay,
    this.debounce = const Duration(seconds: 3),
  }) : _sendRequest = send,
       _delay = delay ?? Future<void>.delayed;

  /// R04: three attempts, sleeping `attempt * 2 s` between them.
  static const maxAttempts = 3;
  static const retryStep = Duration(seconds: 2);

  /// R04: the pump splices 100 entries and waits a second between batches.
  static const bulkBatchSize = DiscordDesktopRestRequest.maxBulkAckEntries;
  static const bulkBatchSpacing = Duration(seconds: 1);

  final DiscordReadStateAckSender _sendRequest;
  final DelayFunction _delay;
  final Duration debounce;

  final Map<String, DiscordPendingAck> _pending = {};
  final Map<String, Timer> _timers = {};
  final Queue<Map<String, Object?>> _bulk = Queue();

  String? _token;
  String? _userId;

  /// Bumped by every session rebind. Work that was already in flight compares
  /// against the value it started with, because clearing the queues cannot
  /// recall a batch that has already been spliced out of them.
  int _generation = 0;
  bool _closed = false;
  Future<void>? _inFlight;
  Future<void>? _bulkDrain;

  /// The rolling ACK token, or null before the first response of a session.
  String? get token => _token;

  /// Whether anything is still waiting to be sent.
  bool get hasPendingWork =>
      _pending.isNotEmpty ||
      _bulk.isNotEmpty ||
      _inFlight != null ||
      _bulkDrain != null;

  /// Rebinds the session this queue is acking for.
  ///
  /// R04: the token resets on every connect and whenever the logged-in user
  /// changes, and a response that arrives after either must not be written
  /// back. Pending work is dropped with it — an ack aimed at the previous
  /// session's channels is not something the new one should send.
  void bindSession(String? userId) {
    // Rebinding with the same user is a reconnect, not a no-op: the token is
    // per session and the server rejects one carried over from the last.
    if (_userId == userId && _token == null && _pending.isEmpty) return;
    _userId = userId;
    _token = null;
    _generation++;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _pending.clear();
    _bulk.clear();
  }

  /// Queues [ack], replacing any pending acknowledgement for the same channel.
  ///
  /// [immediate] collapses the debounce to zero, which is what a channel with
  /// mentions and an explicit "mark as read" both need.
  void schedule(DiscordPendingAck ack, {bool immediate = false}) {
    if (_closed) return;
    _pending[ack.channelId] = ack;
    if (_timers.containsKey(ack.channelId) && !immediate) return;
    _timers.remove(ack.channelId)?.cancel();
    _timers[ack.channelId] = Timer(
      immediate ? Duration.zero : debounce,
      () => unawaited(_flushChannel(ack.channelId)),
    );
  }

  /// Cancels a pending acknowledgement, for a channel another session has just
  /// deliberately marked unread.
  void cancel(String channelId) {
    _timers.remove(channelId)?.cancel();
    _pending.remove(channelId);
  }

  /// Sends one request through the retry policy, for the routes that carry no
  /// debounce of their own: the non-channel acks, mark-unread and the settings
  /// patches.
  Future<void> sendNow(DiscordDesktopRestRequest request) =>
      _serialize(() => _attempt(request));

  /// Queues bulk-ack entries and starts the pump if it is not already running.
  void enqueueBulk(Iterable<Map<String, Object?>> entries) {
    if (_closed) return;
    _bulk.addAll(entries);
    _startBulkDrain();
  }

  /// Sends everything still on a timer, then drains the bulk queue.
  ///
  /// Failures are absorbed. This runs on shutdown and on window-hide, where
  /// the caller has nothing useful to do with a rejected acknowledgement and
  /// every remaining one still deserves its turn.
  Future<void> flush() async {
    for (final channelId in _pending.keys.toList(growable: false)) {
      _timers.remove(channelId)?.cancel();
      await _quietly(_flushChannel(channelId));
    }
    _startBulkDrain();
    await _quietly(_bulkDrain);
    await _quietly(_inFlight);
  }

  Future<void> close() async {
    _closed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _pending.clear();
    _bulk.clear();
    await _quietly(_bulkDrain);
    await _quietly(_inFlight);
  }

  static Future<void> _quietly(Future<void>? operation) async {
    if (operation == null) return;
    try {
      await operation;
    } on Object {
      // Already reported by whoever owns the request.
    }
  }

  void _startBulkDrain() {
    if (_bulkDrain != null || _bulk.isEmpty || _closed) return;
    final drain = _drainBulk();
    _bulkDrain = drain;
    unawaited(
      drain.whenComplete(() {
        if (identical(_bulkDrain, drain)) _bulkDrain = null;
      }),
    );
  }

  Future<void> _flushChannel(String channelId) async {
    _timers.remove(channelId);
    final ack = _pending.remove(channelId);
    if (ack == null || _closed) return;
    final generation = _generation;
    final sessionUserId = _userId;
    final tokenBefore = _token;
    await _serialize(() async {
      if (generation != _generation) return;
      final body = await _attempt(
        DiscordDesktopRestRequest.ackMessage(
          channelId: ack.channelId,
          messageId: ack.messageId,
          readStateToken: tokenBefore,
          lastViewed: ack.lastViewed,
          flags: ack.flags,
        ),
      );
      final next = body?['token'];
      if (generation != _generation) return;
      // Compare-and-set on both the token and the session. A response that
      // overtook a newer ack, or that belongs to an account that has since been
      // switched away from, would otherwise resurrect a stale token and make
      // every later ack fail in a way nothing here can observe.
      if (next is String && _token == tokenBefore && _userId == sessionUserId) {
        _token = next;
      }
    });
  }

  Future<void> _drainBulk() async {
    final generation = _generation;
    while (_bulk.isNotEmpty && !_closed && generation == _generation) {
      final batch = <Map<String, Object?>>[];
      while (batch.length < bulkBatchSize && _bulk.isNotEmpty) {
        batch.add(_bulk.removeFirst());
      }
      try {
        await _serialize(() async {
          // The splice already happened, so the queue cannot be un-drained by
          // a rebind; refusing to send is the only way to honour one that
          // landed between here and the request going out.
          if (generation != _generation) return;
          await _attempt(DiscordDesktopRestRequest.ackBulk(batch));
        });
      } on Object {
        // R04: a batch that fails after its retries clears the whole queue.
        // The alternative — retrying forever — turns one rejected entry into
        // a request loop that never ends.
        _bulk.clear();
        return;
      }
      if (_bulk.isNotEmpty) await _delay(bulkBatchSpacing);
    }
  }

  /// Keeps requests strictly ordered. Two acks for the same channel racing each
  /// other can land in either order at the server, and the loser would rewind
  /// the cursor the winner had just advanced.
  Future<void> _serialize(Future<void> Function() operation) {
    final previous = _inFlight;
    final next = Future<void>(() async {
      if (previous != null) {
        try {
          await previous;
        } on Object {
          // The previous request's failure is its own caller's problem.
        }
      }
      await operation();
    });
    _inFlight = next;
    return next.whenComplete(() {
      if (identical(_inFlight, next)) _inFlight = null;
    });
  }

  Future<Map<String, Object?>?> _attempt(
    DiscordDesktopRestRequest request,
  ) async {
    final generation = _generation;
    // Seeded rather than nullable: every exit from the loop below throws, and
    // a null here would need a branch that cannot be reached or tested.
    Object lastError = StateError('Read-state acknowledgement failed');
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (_closed) return null;
      if (_generation != generation) {
        throw StateError('Read-state acknowledgement abandoned: user changed');
      }
      try {
        return await _sendRequest(request);
      } on DiscordApiException catch (error) {
        lastError = error;
        // A rejection the server will repeat is not worth two more round
        // trips; only a transient failure earns the backoff.
        if (error.statusCode < 500 && error.statusCode != 429) rethrow;
      } on Object catch (error) {
        lastError = error;
      }
      if (attempt + 1 < maxAttempts) await _delay(retryStep * (attempt + 1));
    }
    AppLog.warning(
      'discord.readstate',
      'Discord read-state ${request.method} ${request.path} failed after '
      '$maxAttempts attempts: $lastError',
      error: lastError,
    );
    throw lastError;
  }
}
