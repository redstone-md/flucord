import 'dart:async';

import '../../app_log.dart';
import '../../domain/go_live_stream.dart';
import '../../domain/voice_connection.dart';
import 'discord_rtp_packet.dart';
import 'discord_stream_rtc_session.dart';
import 'discord_voice_socket_factory.dart';

/// The credentials a stream connection needs from the account's live session.
///
/// The session id is the main gateway's, the same one voice identifies with:
/// a stream is a second connection of the same session, not a second session.
typedef DiscordStreamIdentity = ({String sessionId, String userId});

/// Makes a socket factory for a watched stream's connection.
typedef DiscordStreamSocketFactoryProvider =
    DiscordVoiceSocketFactory? Function();

/// An endpoint Discord handed out for this account's own stream to be sent
/// on, with the credentials to dial it.
typedef DiscordSenderEndpoint = ({
  GoLiveStreamKey key,
  VoiceServerCredentials credentials,
});

/// One watched connection and the service's ear on it. The service listens
/// apart from the router: a ready settles a recovery, and a session-ended
/// close starts one.
final class _Held {
  _Held(this.session, this.events);

  final DiscordStreamRtcSession session;
  final StreamSubscription<VoiceSignalingEvent> events;
}

/// One key's credential recovery: how many times fresh credentials have
/// been asked for, and the timer that asks again when nothing answers. The
/// count is what keeps a stream refused every fresh endpoint from turning
/// the recovery into a loop; a connection that reaches ready clears it.
final class _Recovery {
  int attempts = 0;
  Timer? fallback;
}

/// Decides what each stream endpoint is for, and holds the watched ones.
///
/// Discord answers a create and a watch with the same endpoint shape, so the
/// key decides the role: this account's own key is the sender's endpoint, and
/// is handed out on [senderEndpoints] for the Sender to be opened on; anybody
/// else's is watched here. Nothing is ever watched on the own key (ADR-0001).
final class DiscordStreamRtcService {
  DiscordStreamRtcService({
    required GoLiveRepository? Function() repositoryProvider,
    required DiscordStreamIdentity? Function() identityProvider,
    DiscordStreamSocketFactoryProvider? socketFactoryProvider,

    /// Whether a stream key is still held by this client: asked to watch, and
    /// not stopped since. An endpoint for anything else is nobody's to
    /// receive, and opens a connection nothing would ever stop.
    bool Function(GoLiveStreamKey key)? isWatched,

    /// How long a recovery waits for fresh credentials before asking again.
    /// A seam for the tests; the production wait is two seconds.
    Duration reissueFallbackDelay = const Duration(seconds: 2),
  }) : _repositoryProvider = repositoryProvider,
       _identityProvider = identityProvider,
       _socketFactoryProvider = socketFactoryProvider,
       _isWatched = isWatched,
       _reissueFallbackDelay = reissueFallbackDelay;

  final GoLiveRepository? Function() _repositoryProvider;
  final DiscordStreamIdentity? Function() _identityProvider;
  final DiscordStreamSocketFactoryProvider? _socketFactoryProvider;
  final bool Function(GoLiveStreamKey key)? _isWatched;
  final Duration _reissueFallbackDelay;

  /// The connections streams are being watched on, by key.
  final Map<String, _Held> _held = {};

  /// The opens in flight, by key. Opens for one key run one after another.
  final Map<GoLiveStreamKey, Future<void>> _opening = {};

  /// Which endpoint request each key is on. An open captures its own and
  /// stands down when another request, or a stop, has superseded it.
  final Map<GoLiveStreamKey, int> _generations = {};

  /// Each key's credential recovery, while it has one.
  final Map<GoLiveStreamKey, _Recovery> _recovering = {};

  /// The recoveries one key may ask for before the watch is given up on.
  static const maxRecoveries = 3;

  final StreamController<DiscordStreamRtcSession> _opened =
      StreamController.broadcast();
  final StreamController<DiscordSenderEndpoint> _senderEndpoints =
      StreamController.broadcast();

  GoLiveRepository? _repository;
  StreamSubscription<GoLiveServer>? _servers;
  StreamSubscription<GoLiveStream>? _streamUpdates;
  bool _closed = false;

  /// Fires whenever a watched stream's connection has been opened.
  ///
  /// The endpoint arrives asynchronously, well after the ask, so callers
  /// wait on this rather than on the call that asked.
  Stream<DiscordStreamRtcSession> get opened => _opened.stream;

  /// Fires with each endpoint this account's own stream is to be sent on.
  Stream<DiscordSenderEndpoint> get senderEndpoints => _senderEndpoints.stream;

  /// Binds to the current transport, if it changed. Cheap to call repeatedly.
  bool reconcile() {
    if (_closed) return false;
    final repository = _repositoryProvider();
    if (identical(repository, _repository)) return _repository != null;
    unawaited(_servers?.cancel());
    unawaited(_streamUpdates?.cancel());
    _repository = repository;
    _servers = repository?.servers.listen(_acceptServer);
    _streamUpdates = repository?.updates.listen(_acceptStreamUpdate);
    return repository != null;
  }

  /// The connection [key] is being watched on, or null when there is none.
  DiscordStreamRtcSession? sessionFor(GoLiveStreamKey key) =>
      _held[key.value]?.session;

  /// Pictures arriving for [key]. Empty until the endpoint has answered.
  Stream<(String, DiscordRtpFrame)> videoFor(GoLiveStreamKey key) =>
      _held[key.value]?.session.video ??
      const Stream<(String, DiscordRtpFrame)>.empty();

  /// Drops the connection [key] is being watched on, leaving any others alone.
  ///
  /// The watch holder's own act: the watch it ends was ended here, so the
  /// close is marked as one the router must not report as well.
  Future<void> stop(GoLiveStreamKey key) async {
    _generations[key] = (_generations[key] ?? 0) + 1;
    _recovering.remove(key)?.fallback?.cancel();
    await _drop(key, endsTheWatch: false);
  }

  Future<void> _drop(GoLiveStreamKey key, {required bool endsTheWatch}) async {
    final held = _held.remove(key.value);
    unawaited(held?.events.cancel());
    // A fresh connection answers the ask the fallback was waiting to repeat.
    _recovering[key]?.fallback?.cancel();
    // A close that ends the watch ends its recovery with it.
    if (endsTheWatch) _recovering.remove(key);
    final session = held?.session;
    if (session == null) return;
    if (endsTheWatch) {
      await session.close();
    } else {
      await session.closeKeepingWatch();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _servers?.cancel();
    await _streamUpdates?.cancel();
    for (final recovery in _recovering.values) {
      recovery.fallback?.cancel();
    }
    _recovering.clear();
    for (final held in _held.values.toList(growable: false)) {
      unawaited(held.events.cancel());
      await held.session.close();
    }
    _held.clear();
    await _opened.close();
    await _senderEndpoints.close();
  }

  /// An update for a stream the repository no longer holds is that stream's
  /// end: a local `endStream` and a `STREAM_DELETE` dispatch both publish the
  /// final state after removing it. The connection must not outlive its
  /// stream, whose credentials died with it. This close is news to the
  /// router, and the watch ends with it.
  ///
  /// While a recovery for the key has an ask outstanding, the removal is
  /// that recovery's own withdrawal echoed back: the watch goes on, and the
  /// fallback is what catches a stream that ended for real.
  void _acceptStreamUpdate(GoLiveStream stream) {
    if (_closed) return;
    if (_recovering[stream.key]?.fallback?.isActive ?? false) return;
    if (_repository?.streams.containsKey(stream.key.value) ?? true) return;
    unawaited(_drop(stream.key, endsTheWatch: true));
  }

  void _acceptServer(GoLiveServer server) {
    if (_closed) return;
    final identity = _identityProvider();
    // Without the session id there is nothing to identify with. Dropping the
    // endpoint is right: it is short-lived, and Discord reissues one on the
    // next watch or create rather than expecting the client to hold it.
    if (identity == null) {
      _diagnose(
        'endpoint for ${server.key.userId}',
        'no session to identify with',
      );
      return;
    }
    final credentials = _credentialsFor(server, identity);
    if (server.key.userId == identity.userId) {
      _senderEndpoints.add((key: server.key, credentials: credentials));
      return;
    }
    // An endpoint for a stream this client does not hold is not worth a
    // connection: opened, it would dial and live on with nothing stopping it.
    // Discord reissues the endpoint on the next ask.
    if (!_stillWanted(server.key)) {
      _diagnose('endpoint for an unheld stream ignored', server.key.userId);
      return;
    }
    _generations[server.key] = (_generations[server.key] ?? 0) + 1;
    _open(server.key, credentials);
  }

  /// Whether the stream [key] names still exists and is still held: an
  /// endpoint is a connection's worth of state, and Discord reissues one on
  /// the next ask rather than expecting the client to hold it.
  bool _stillWanted(GoLiveStreamKey key) {
    if (!(_repository?.streams.containsKey(key.value) ?? false)) return false;
    return _isWatched?.call(key) ?? true;
  }

  static VoiceServerCredentials _credentialsFor(
    GoLiveServer server,
    DiscordStreamIdentity identity,
  ) => VoiceServerCredentials(
    // The RTC server and channel Discord named for this stream in
    // STREAM_CREATE, falling back to the guild and the voice channel when
    // no create was seen. Those two are what identify carries, and the
    // wrong pair is refused: `sessionInvalid` for the guild,
    // `identifyRefused` for the rest.
    guildId: server.rtcServerId.isNotEmpty
        ? server.rtcServerId
        : server.key.guildId,
    channelId: server.rtcChannelId.isNotEmpty
        ? server.rtcChannelId
        : server.key.channelId,
    userId: identity.userId,
    sessionId: identity.sessionId,
    token: server.token,
    endpoint: server.endpoint,
  );

  void _diagnose(String what, [Object? detail]) {
    AppLog.warning('stream', '$what${detail == null ? '' : ': $detail'}');
  }

  /// Queues the connection for [key] behind any open already running for it.
  ///
  /// Two endpoints in one socket batch would otherwise both get past the
  /// stop: the map would hold the second while two live sockets went on
  /// receiving, decrypting twice and answering every NACK twice.
  void _open(GoLiveStreamKey key, VoiceServerCredentials credentials) {
    final generation = _generations[key] ?? 0;
    final queued = _opening[key] ?? Future<void>.value();
    final open = queued.then((_) => _openNow(key, credentials, generation));
    _opening[key] = open;
    unawaited(
      open.whenComplete(() {
        if (identical(_opening[key], open)) _opening.remove(key);
      }),
    );
  }

  Future<void> _openNow(
    GoLiveStreamKey key,
    VoiceServerCredentials credentials,
    int generation,
  ) async {
    try {
      if (_closed) return;
      // Superseded while queued: a newer endpoint, or a stop, owns the key.
      if (generation != (_generations[key] ?? 0)) return;
      // A replaced endpoint replaces the connection: two sockets for one
      // stream would both be receiving. The swap close is not news to the
      // router; the fresh connection below takes the watch over.
      await _drop(key, endsTheWatch: false);
      // The waits above are crossings: the stream may have ended, or the
      // watch been stopped, while this open waited for its turn.
      if (_closed || generation != (_generations[key] ?? 0)) return;
      if (!_stillWanted(key)) return;
      final session = DiscordStreamRtcSession(
        key: key,
        credentials: credentials,
        // Receiving uses the same factory as the call, so the two agree about
        // DAVE without this module knowing a version number.
        socketFactory:
            _socketFactoryProvider?.call() ?? DiscordVoiceGatewaySocketFactory(),
      );
      _held[key.value] = _Held(
        session,
        session.events.listen((event) => _onSessionEvent(key, event)),
      );
      if (!_opened.isClosed) _opened.add(session);
      await session.connect();
    } on Object catch (error) {
      // The connection reports its own failures as statuses; a throw here
      // would strand the opens queued behind it.
      _diagnose('connection failed to open', error);
    }
  }

  /// What the service hears on its connections' events, apart from what the
  /// router hears.
  void _onSessionEvent(GoLiveStreamKey key, VoiceSignalingEvent event) {
    if (event is VoiceTransportReadyEvent) {
      _recovering[key]?.attempts = 0;
      return;
    }
    if (event is! VoiceCredentialsNeededEvent) return;
    _recover(
      key,
      _recovering.putIfAbsent(key, _Recovery.new),
    );
  }

  /// Recovers a connection whose session Discord ended: fresh credentials are
  /// asked for, and asked for again when nothing answers, until the watch is
  /// given up on.
  void _recover(GoLiveStreamKey key, _Recovery recovery) {
    recovery.attempts++;
    if (recovery.attempts > maxRecoveries) {
      _diagnose(
        'giving up after $maxRecoveries re-issued credentials',
        key.userId,
      );
      // The watch cannot go on a connection that keeps dying: the close is
      // news to the router, and the watch ends with it.
      unawaited(_drop(key, endsTheWatch: true));
      return;
    }
    unawaited(_askForFreshCredentials(key));
    recovery.fallback?.cancel();
    recovery.fallback = Timer(_reissueFallbackDelay, () {
      if (_closed || !identical(_recovering[key], recovery)) return;
      // The stream the ask was for is gone: the watch ends with it.
      if (!_stillWanted(key)) {
        unawaited(_drop(key, endsTheWatch: true));
        return;
      }
      _recover(key, recovery);
    });
  }

  /// Asks the gateway to re-issue the stream's credentials, the same
  /// recovery the call's credentials follow: the main gateway is made to
  /// hand out a fresh endpoint, and the connection is rebuilt from it.
  Future<void> _askForFreshCredentials(GoLiveStreamKey key) async {
    final repository = _repository;
    if (repository == null || _closed) return;
    if (!_stillWanted(key)) return;
    try {
      // Discord answers no second watch for a stream it still counts this
      // client under, so the withdrawal goes first: the leave and rejoin
      // that is the one ask it cannot answer with silence.
      await repository.stopWatching(key);
      // The withdrawal is a crossing: the watch may have been stopped while
      // it was in flight.
      if (_closed || !_stillWanted(key)) return;
      await repository.watchStream(key);
      _diagnose('asked for fresh credentials', key.userId);
    } on Object catch (error) {
      _diagnose('credential re-issue refused', error);
    }
  }
}
