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
  }) : _repositoryProvider = repositoryProvider,
       _identityProvider = identityProvider,
       _socketFactoryProvider = socketFactoryProvider;

  final GoLiveRepository? Function() _repositoryProvider;
  final DiscordStreamIdentity? Function() _identityProvider;
  final DiscordStreamSocketFactoryProvider? _socketFactoryProvider;

  /// The connections streams are being watched on, by key.
  final Map<String, DiscordStreamRtcSession> _sessions = {};

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
      _sessions[key.value];

  /// Pictures arriving for [key]. Empty until the endpoint has answered.
  Stream<(String, DiscordRtpFrame)> videoFor(GoLiveStreamKey key) =>
      _sessions[key.value]?.video ??
      const Stream<(String, DiscordRtpFrame)>.empty();

  /// Drops the connection [key] is being watched on, leaving any others alone.
  Future<void> stop(GoLiveStreamKey key) async {
    final session = _sessions.remove(key.value);
    await session?.close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _servers?.cancel();
    await _streamUpdates?.cancel();
    for (final session in _sessions.values.toList(growable: false)) {
      await session.close();
    }
    _sessions.clear();
    await _opened.close();
    await _senderEndpoints.close();
  }

  /// An update for a stream the repository no longer holds is that stream's
  /// end: a local `endStream` and a `STREAM_DELETE` dispatch both publish the
  /// final state after removing it. The connection must not outlive its
  /// stream, whose credentials died with it.
  void _acceptStreamUpdate(GoLiveStream stream) {
    if (_closed) return;
    if (_repository?.streams.containsKey(stream.key.value) ?? true) return;
    unawaited(stop(stream.key));
  }

  void _acceptServer(GoLiveServer server) {
    if (_closed) return;
    final identity = _identityProvider();
    _diagnose(
      'endpoint for ${server.key.userId}',
      identity == null ? 'no session to identify with' : 'opening',
    );
    // Without the session id there is nothing to identify with. Dropping the
    // endpoint is right: it is short-lived, and Discord reissues one on the
    // next watch or create rather than expecting the client to hold it.
    if (identity == null) return;
    final credentials = _credentialsFor(server, identity);
    if (server.key.userId == identity.userId) {
      _senderEndpoints.add((key: server.key, credentials: credentials));
      return;
    }
    unawaited(_open(server.key, credentials));
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

  Future<void> _open(
    GoLiveStreamKey key,
    VoiceServerCredentials credentials,
  ) async {
    // A replaced endpoint replaces the connection: two sockets for one
    // stream would both be receiving.
    await stop(key);
    if (_closed) return;
    final session = DiscordStreamRtcSession(
      key: key,
      credentials: credentials,
      // Receiving uses the same factory as the call, so the two agree about
      // DAVE without this module knowing a version number.
      socketFactory:
          _socketFactoryProvider?.call() ?? DiscordVoiceGatewaySocketFactory(),
    );
    _sessions[key.value] = session;
    if (!_opened.isClosed) _opened.add(session);
    await session.connect();
  }
}
