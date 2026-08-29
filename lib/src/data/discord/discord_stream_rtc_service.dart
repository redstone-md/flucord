import 'dart:async';


import '../../domain/go_live_stream.dart';
import '../../domain/voice_connection.dart';
import 'discord_rtp_packet.dart';
import 'discord_stream_rtc_session.dart';
import 'discord_voice_socket_factory.dart';
import '../../app_log.dart';

/// The credentials a stream connection needs from the account's live session.
///
/// The session id is the main gateway's, the same one voice identifies with —
/// a stream is a second connection of the same session, not a second session.
typedef DiscordStreamIdentity = ({String sessionId, String userId});

/// Makes a socket factory for a stream connection.
///
/// The service asks the sending provider only for the connection that will
/// announce video. The regular provider serves receivers, including the
/// second connection for this account's own key (ADR-0001).
typedef DiscordStreamSocketFactoryProvider =
    DiscordVoiceSocketFactory? Function();

/// Holds the RTC connections Go Live streams run on.
///
/// One per stream, opened when Discord answers with an endpoint and closed
/// when the stream ends or the viewer stops watching. Sending and watching are
/// the same connection type, so both go through here: what differs is only who
/// declares video on it.
///
/// This account's own key carries two of them while it shares, one to send on
/// and one to watch the same stream back (ADR-0001). They are held apart
/// rather than under one map entry, so opening the second does not close the
/// share.
final class DiscordStreamRtcService {
  DiscordStreamRtcService({
    required GoLiveRepository? Function() repositoryProvider,
    required DiscordStreamIdentity? Function() identityProvider,
    DiscordStreamSocketFactoryProvider? socketFactoryProvider,
    DiscordStreamSocketFactoryProvider? sendingSocketFactoryProvider,
  }) : _repositoryProvider = repositoryProvider,
       _identityProvider = identityProvider,
       _socketFactoryProvider = socketFactoryProvider,
       _sendingSocketFactoryProvider = sendingSocketFactoryProvider;

  final GoLiveRepository? Function() _repositoryProvider;
  final DiscordStreamIdentity? Function() _identityProvider;
  final DiscordStreamSocketFactoryProvider? _socketFactoryProvider;
  final DiscordStreamSocketFactoryProvider? _sendingSocketFactoryProvider;

  /// The connections streams are being watched on, by key.
  final Map<String, DiscordStreamRtcSession> _sessions = {};

  /// The connection this account's share is sent on, when it is sharing.
  DiscordStreamRtcSession? _sending;

  /// Watch commands for this account's own key that have not received an
  /// endpoint yet. They identify a receiving connection without guessing from
  /// endpoint arrival order.
  final Map<String, int> _pendingWatches = {};

  /// Claims the first own endpoint before [_open] crosses an async close, so
  /// two near-simultaneous endpoint events cannot both become senders.
  bool _sendingOpening = false;

  final StreamController<DiscordStreamRtcSession> _opened =
      StreamController.broadcast();

  GoLiveRepository? _repository;
  StreamSubscription<GoLiveServer>? _servers;
  StreamSubscription<GoLiveStream>? _streamUpdates;
  bool _closed = false;

  /// Fires whenever a stream connection has been opened.
  ///
  /// The endpoint arrives asynchronously, well after the button was pressed,
  /// so callers wait on this rather than on the call that started the stream.
  Stream<DiscordStreamRtcSession> get opened => _opened.stream;

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

  /// Records a watch command before its receiving endpoint arrives.
  ///
  /// Only the own key needs this intent. Other participants are always
  /// receivers, and keeping their commands here would leave stale role hints.
  void noteWatch(GoLiveStreamKey key) {
    if (_identityProvider()?.userId != key.userId) return;
    _pendingWatches.update(
      key.value,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  /// The connection carrying [key], or null when there is none.
  ///
  /// Where this account's own key carries two, this is the one it sends on:
  /// a caller looking for the connection is looking for the sender's, and
  /// what the other one receives is read through the viewer.
  DiscordStreamRtcSession? sessionFor(GoLiveStreamKey key) {
    final sending = _sending;
    return sending?.key == key ? sending : _sessions[key.value];
  }

  /// Pictures arriving for [key]. Empty until the endpoint has answered.
  ///
  /// The share's own connection has nothing to read: its pictures are drained
  /// by whatever sends them, so this is the one being watched.
  Stream<(String, DiscordRtpFrame)> videoFor(GoLiveStreamKey key) =>
      _sessions[key.value]?.video ??
      const Stream<(String, DiscordRtpFrame)>.empty();

  /// Drops the connection [key] is being watched on, leaving any others alone.
  Future<void> stop(GoLiveStreamKey key) async {
    final session = _sessions.remove(key.value);
    await session?.close();
  }

  /// Ends the connection this account's share is sent on.
  Future<void> _stopSending() async {
    final sending = _sending;
    _sending = null;
    await sending?.close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _servers?.cancel();
    await _streamUpdates?.cancel();
    _pendingWatches.clear();
    _sendingOpening = false;
    await _stopSending();
    for (final session in _sessions.values.toList(growable: false)) {
      await session.close();
    }
    _sessions.clear();
    await _opened.close();
  }

  /// An update for a stream the repository no longer holds is that stream's
  /// end: a local `endStream` and a `STREAM_DELETE` dispatch both publish the
  /// final state after removing it. The connection must not outlive its
  /// stream, whose credentials died with it.
  void _acceptStreamUpdate(GoLiveStream stream) {
    if (_closed) return;
    if (_repository?.streams.containsKey(stream.key.value) ?? true) return;
    _pendingWatches.remove(stream.key.value);
    // A stream that ended takes both of its connections, the one it was sent
    // on and the one this client was watching it back on.
    if (_sending?.key == stream.key || _sendingOpening) {
      _sendingOpening = false;
      unawaited(_stopSending());
    }
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
    final sending = _claimSender(server.key, identity.userId);
    unawaited(_open(server, identity, sending: sending));
  }

  bool _claimSender(GoLiveStreamKey key, String userId) {
    if (key.userId != userId) return false;
    final pending = _pendingWatches[key.value] ?? 0;
    if (pending > 0) {
      if (pending == 1) {
        _pendingWatches.remove(key.value);
      } else {
        _pendingWatches[key.value] = pending - 1;
      }
      return false;
    }
    if (_sendingOpening) return false;
    // A different key means the share moved or restarted, so it replaces the
    // old sender connection. A new endpoint for the same key is also the
    // sender's replacement unless a pending watch marked it as receiving.
    _sendingOpening = true;
    return true;
  }

  void _diagnose(String what, [Object? detail]) {
    AppLog.warning(
      'stream',
      '$what${detail == null ? '' : ': $detail'}',
    );
  }

  Future<void> _open(
    GoLiveServer server,
    DiscordStreamIdentity identity, {
    required bool sending,
  }) async {
    // Role is resolved before opening: a pending own-key watch is receiving,
    // otherwise an own endpoint is the sender connection (ADR-0001).
    if (sending) {
      // A moved or restarted share replaces the old sender and own receiver.
      await _stopSending();
      for (final key in [
        for (final session in _sessions.values)
          if (session.key.userId == identity.userId) session.key,
      ]) {
        await stop(key);
      }
      _sendingOpening = false;
    } else {
      await stop(server.key);
    }
    if (_closed) return;
    final session = DiscordStreamRtcSession(
      key: server.key,
      credentials: VoiceServerCredentials(
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
      ),
      // No call plane to agree with, so DAVE-less sockets: version 0, the
      // transport cipher alone. The sender has its own media-plane factory;
      // the receiver must use the plain factory so opening it cannot replace
      // the sender's current encoder connection.
      socketFactory:
          (sending
                  ? _sendingSocketFactoryProvider
                  : _socketFactoryProvider)
              ?.call() ??
          _socketFactoryProvider?.call() ??
          DiscordVoiceGatewaySocketFactory(),
      sending: sending,
    );
    if (sending) {
      _sending = session;
    } else {
      _sessions[server.key.value] = session;
    }
    if (!_opened.isClosed) _opened.add(session);
    await session.connect();
  }
}
