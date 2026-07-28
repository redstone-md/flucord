import 'dart:async';

import '../../domain/go_live_stream.dart';

/// The gateway frames Go Live needs.
///
/// These are opcodes rather than REST calls: a stream is negotiated entirely
/// over the socket the session is already holding, which is also why ending
/// one is a frame and not a DELETE.
abstract interface class DiscordGoLiveGateway {
  /// Opcode 18.
  void sendStreamCreate({
    required String type,
    required String channelId,
    String? guildId,
    String? preferredRegion,
  });

  /// Opcode 19.
  void sendStreamDelete(String streamKey);

  /// Opcode 20.
  void sendStreamWatch(String streamKey);

  /// Opcode 21.
  void sendStreamPing(String streamKey);

  /// Opcode 22.
  void sendStreamSetPaused(String streamKey, {required bool paused});

  /// The account this session is signed in as, or `null` before READY.
  String? get currentUserId;
}

/// Go Live over the desktop-user session.
///
/// The stream is a second, independent RTC connection: the voice connection
/// carries the room's audio and this one carries the picture, with its own
/// endpoint and token. Keeping them apart is what lets a stream end without
/// disturbing the call it is inside.
final class DiscordGoLiveService implements GoLiveRepository {
  DiscordGoLiveService(this._gateway);

  final DiscordGoLiveGateway _gateway;
  final StreamController<GoLiveStream> _updates = StreamController.broadcast();
  final StreamController<GoLiveServer> _servers = StreamController.broadcast();
  final Map<String, GoLiveStream> _streams = {};

  @override
  Map<String, GoLiveStream> get streams => Map.unmodifiable(_streams);

  @override
  Stream<GoLiveStream> get updates => _updates.stream;

  @override
  Stream<GoLiveServer> get servers => _servers.stream;

  @override
  Future<GoLiveStreamKey> startStream({
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) async {
    final userId = _gateway.currentUserId;
    if (userId == null || userId.isEmpty) {
      throw StateError('The gateway session is not established');
    }
    // The key is composed locally because every later frame needs it, and
    // Discord's answer arrives asynchronously: waiting for STREAM_CREATE
    // before knowing what to ping would leave a window with no handle.
    final key = guildId == null
        ? GoLiveStreamKey.call(channelId: channelId, userId: userId)
        : GoLiveStreamKey.guild(
            guildId: guildId,
            channelId: channelId,
            userId: userId,
          );
    _gateway.sendStreamCreate(
      type: guildId == null ? 'call' : 'guild',
      channelId: channelId,
      guildId: guildId,
      preferredRegion: preferredRegion,
    );
    return key;
  }

  @override
  Future<void> watchStream(GoLiveStreamKey key) async =>
      _gateway.sendStreamWatch(key.value);

  @override
  Future<void> pingStream(GoLiveStreamKey key) async =>
      _gateway.sendStreamPing(key.value);

  @override
  Future<void> setPaused(GoLiveStreamKey key, {required bool paused}) async {
    _gateway.sendStreamSetPaused(key.value, paused: paused);
    final existing = _streams[key.value];
    // Applied locally rather than waiting for STREAM_UPDATE: pausing is a
    // local decision Discord is being told about, not asked for.
    if (existing != null) _publish(existing.copyWith(isPaused: paused));
  }

  @override
  Future<void> endStream(GoLiveStreamKey key) async {
    _gateway.sendStreamDelete(key.value);
    final removed = _streams.remove(key.value);
    if (removed != null && !_updates.isClosed) {
      _updates.add(removed.copyWith(viewerIds: const []));
    }
  }

  /// Folds a gateway dispatch in.
  ///
  /// Returns the stream it changed, or `null` for anything else.
  GoLiveStream? accept(String eventName, Map<String, Object?> data) =>
      switch (eventName) {
        'STREAM_CREATE' => _acceptCreate(data),
        'STREAM_UPDATE' => _acceptUpdate(data),
        'STREAM_SERVER_UPDATE' => _acceptServer(data),
        'STREAM_DELETE' => _acceptDelete(data),
        _ => null,
      };

  Future<void> close() async {
    if (!_updates.isClosed) await _updates.close();
    if (!_servers.isClosed) await _servers.close();
  }

  GoLiveStream? _acceptCreate(Map<String, Object?> data) {
    final key = _key(data);
    if (key == null) return null;
    return _publish(
      GoLiveStream(
        key: key,
        rtcServerId: _text(data['rtc_server_id']),
        region: _text(data['region']),
        viewerIds: _strings(data['viewer_ids']),
        isPaused: data['paused'] == true,
      ),
    );
  }

  /// `STREAM_UPDATE` carries only what changed, so the held stream is the
  /// starting point rather than the payload.
  GoLiveStream? _acceptUpdate(Map<String, Object?> data) {
    final key = _key(data);
    if (key == null) return null;
    final existing = _streams[key.value] ?? GoLiveStream(key: key);
    return _publish(
      existing.copyWith(
        region: data.containsKey('region') ? _text(data['region']) : null,
        viewerIds: data.containsKey('viewer_ids')
            ? _strings(data['viewer_ids'])
            : null,
        isPaused: data.containsKey('paused') ? data['paused'] == true : null,
      ),
    );
  }

  /// The endpoint the picture is sent to. Reported separately from the stream
  /// because Discord assigns it after the stream exists, and reassigns it on a
  /// region change without the stream itself changing.
  GoLiveStream? _acceptServer(Map<String, Object?> data) {
    final key = _key(data);
    if (key == null) return null;
    final endpoint = _text(data['endpoint']);
    final token = _text(data['token']);
    if (endpoint.isEmpty || token.isEmpty) return null;
    if (!_servers.isClosed) {
      _servers.add(GoLiveServer(key: key, endpoint: endpoint, token: token));
    }
    return _streams[key.value];
  }

  GoLiveStream? _acceptDelete(Map<String, Object?> data) {
    final key = _key(data);
    if (key == null) return null;
    final removed = _streams.remove(key.value);
    if (removed == null) return null;
    final ended = removed.copyWith(viewerIds: const []);
    if (!_updates.isClosed) _updates.add(ended);
    return ended;
  }

  GoLiveStream _publish(GoLiveStream stream) {
    _streams[stream.key.value] = stream;
    if (!_updates.isClosed) _updates.add(stream);
    return stream;
  }

  static GoLiveStreamKey? _key(Map<String, Object?> data) {
    final raw = data['stream_key'];
    return raw is String ? GoLiveStreamKey.parse(raw) : null;
  }

  static String _text(Object? value) => value is String ? value : '';

  static List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];
}
