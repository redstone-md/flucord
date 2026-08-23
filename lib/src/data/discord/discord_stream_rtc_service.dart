import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/go_live_stream.dart';
import '../../domain/voice_connection.dart';
import 'discord_rtp_packet.dart';
import 'discord_stream_rtc_session.dart';
import 'discord_voice_socket_factory.dart';

/// The credentials a stream connection needs from the account's live session.
///
/// The session id is the main gateway's, the same one voice identifies with —
/// a stream is a second connection of the same session, not a second session.
typedef DiscordStreamIdentity = ({String sessionId, String userId});

/// Holds the RTC connections Go Live streams run on.
///
/// One per stream, opened when Discord answers with an endpoint and closed
/// when the stream ends or the viewer stops watching. Sending and watching are
/// the same connection type, so both go through here: what differs is only who
/// declares video on it.
final class DiscordStreamRtcService {
  DiscordStreamRtcService({
    required GoLiveRepository? Function() repositoryProvider,
    required DiscordStreamIdentity? Function() identityProvider,
    DiscordVoiceSocketFactory? Function()? socketFactoryProvider,
  }) : _repositoryProvider = repositoryProvider,
       _identityProvider = identityProvider,
       _socketFactoryProvider = socketFactoryProvider;

  final GoLiveRepository? Function() _repositoryProvider;
  final DiscordStreamIdentity? Function() _identityProvider;
  final DiscordVoiceSocketFactory? Function()? _socketFactoryProvider;

  final Map<String, DiscordStreamRtcSession> _sessions = {};
  final StreamController<DiscordStreamRtcSession> _opened =
      StreamController.broadcast();

  GoLiveRepository? _repository;
  StreamSubscription<GoLiveServer>? _servers;
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
    _repository = repository;
    _servers = repository?.servers.listen(_acceptServer);
    return repository != null;
  }

  /// The connection carrying [key], or null when there is none.
  DiscordStreamRtcSession? sessionFor(GoLiveStreamKey key) =>
      _sessions[key.value];

  /// Pictures arriving for [key]. Empty until the endpoint has answered.
  Stream<(String, DiscordRtpFrame)> videoFor(GoLiveStreamKey key) =>
      _sessions[key.value]?.video ??
      const Stream<(String, DiscordRtpFrame)>.empty();

  /// Drops the connection for [key], leaving any others alone.
  Future<void> stop(GoLiveStreamKey key) async {
    final session = _sessions.remove(key.value);
    await session?.close();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _servers?.cancel();
    for (final session in _sessions.values.toList(growable: false)) {
      await session.close();
    }
    _sessions.clear();
    await _opened.close();
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
    unawaited(_open(server, identity));
  }

  void _diagnose(String what, [Object? detail]) {
    final line = 'flucord.stream $what${detail == null ? '' : ': $detail'}';
    developer.log(line, name: 'flucord.stream', level: 900);
    if (kDebugMode) stdout.writeln(line);
  }

  Future<void> _open(
    GoLiveServer server,
    DiscordStreamIdentity identity,
  ) async {
    // A replaced endpoint for a stream already up is a move, so the old
    // connection goes first — two sockets for one stream would both be sending.
    await stop(server.key);
    if (_closed) return;
    final session = DiscordStreamRtcSession(
      key: server.key,
      credentials: VoiceServerCredentials(
        // The RTC server and channel Discord named for this stream in
        // STREAM_CREATE, falling back to the guild and the voice channel when
        // no create was seen. Those two are what identify carries, and the
        // wrong pair is refused: 4006 for the guild, 4017 for the rest.
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
      // transport cipher alone.
      socketFactory: _socketFactoryProvider?.call() ?? DiscordVoiceGatewaySocketFactory(),
    );
    _sessions[server.key.value] = session;
    if (!_opened.isClosed) _opened.add(session);
    await session.connect();
  }
}
