import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_log.dart';
import '../data/discord/discord_rtp_packet.dart';
import '../domain/video_decoder.dart';
import 'watched_session_pipeline.dart';

/// Decrypts one whole picture for the room's group, for the sender named.
typedef CameraGroupDecryptor =
    Uint8List Function(String userId, Uint8List picture);

/// Everybody else's cameras in the voice room.
///
/// One pipeline per person, not one shared: two senders interleave on the
/// same socket, and a single receiver would splice one person's packets into
/// another's picture. The same pipeline a watched stream uses, with pacing
/// off: a camera tile is small and expected to be live, and it recovers from
/// a lost picture the way a stream does. The decoders are made through a
/// factory for the same reason as the encoder. A test host has no H.264
/// decoder, and the controller has to be exercisable without one.
final class RemoteCameraController extends ChangeNotifier {
  RemoteCameraController({
    required Stream<(String, DiscordRtpFrame)> Function() packetsProvider,
    required VideoDecoderService Function() decoderFactory,

    /// Decrypts a whole picture for the room's group, when there is one.
    /// Asked for on every picture rather than bound once: a reconnect
    /// replaces the connection, and a closure over the old one would decrypt
    /// with a key from a session nobody holds anymore.
    CameraGroupDecryptor? Function()? groupDecryptorProvider,

    /// Asks whoever sends on [mediaSsrc] for a keyframe, over the call's
    /// connection (RFC 4585).
    void Function(int mediaSsrc)? requestKeyframe,
  }) : _packetsProvider = packetsProvider,
       _decoderFactory = decoderFactory,
       _groupDecryptorProvider = groupDecryptorProvider,
       _requestKeyframe = requestKeyframe;

  final Stream<(String, DiscordRtpFrame)> Function() _packetsProvider;
  final VideoDecoderService Function() _decoderFactory;
  final CameraGroupDecryptor? Function()? _groupDecryptorProvider;
  final void Function(int mediaSsrc)? _requestKeyframe;

  final Map<String, _RemoteCamera> _cameras = {};
  StreamSubscription<(String, DiscordRtpFrame)>? _subscription;
  bool _listening = false;
  bool _disposed = false;

  /// Who is currently sending a picture this client has drawn at least once.
  List<String> get senders => [
    for (final entry in _cameras.entries)
      if (entry.value.frame != null) entry.key,
  ];

  /// The latest picture from [userId], or `null` if none has decoded yet.
  DecodedVideoFrame? frameFor(String userId) => _cameras[userId]?.frame;

  /// How many payloads have arrived from [userId], which separates "somebody
  /// is sending" from "something has decoded".
  int packetsFrom(String userId) =>
      _cameras[userId]?.pipeline.stats.receivedPackets ?? 0;

  bool get isReceiving => _cameras.values.any((camera) => camera.frame != null);

  /// Starts reading from the live voice session.
  ///
  /// Called again after a reconnect: the previous subscription is dropped and
  /// every camera with it, because the SSRCs it was built around belong to a
  /// socket that has gone.
  void listen() {
    unawaited(_subscription?.cancel());
    _clearCameras();
    _subscription = _packetsProvider().listen(_accept);
    _listening = true;
    _notify();
  }

  /// Whether anything is being read at all.
  bool get isListening => _listening;

  void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _clearCameras();
    _listening = false;
    _notify();
  }

  void _accept((String, DiscordRtpFrame) packet) {
    final (userId, frame) = packet;
    // Opened lazily: a room where nobody turns a camera on should not open
    // a decoder per participant.
    final camera = _cameras.putIfAbsent(userId, () => _open(userId));
    camera.ssrc = frame.header.ssrc;
    camera.pipeline.accept(
      IncomingVideoPacket(
        payload: Uint8List.fromList(frame.payload),
        marker: frame.header.marker,
        rtpTimestamp: frame.header.timestamp,
      ),
    );
  }

  _RemoteCamera _open(String userId) {
    final camera = _RemoteCamera(
      WatchedSessionPipeline(
        decoderFactory: _decoderFactory,
        groupDecryptor: (picture) {
          final decryptor = _groupDecryptorProvider?.call();
          return decryptor == null ? picture : decryptor(userId, picture);
        },
        requestKeyframe: _requestKeyframe == null
            ? null
            : () => _askForKeyframe(userId),
        paced: false,
      ),
    );
    camera.frames = camera.pipeline.frames.listen((picture) {
      camera.frame = picture;
      _notify();
    });
    unawaited(
      camera.pipeline
          .setDecoding(true)
          .catchError(
            (Object error) =>
                AppLog.warning('camera', 'decoder failed for $userId: $error'),
          ),
    );
    return camera;
  }

  void _askForKeyframe(String userId) {
    final ssrc = _cameras[userId]?.ssrc;
    if (ssrc != null) _requestKeyframe?.call(ssrc);
  }

  void _clearCameras() {
    for (final camera in _cameras.values) {
      unawaited(camera.frames?.cancel());
      unawaited(camera.pipeline.close());
    }
    _cameras.clear();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    _clearCameras();
    super.dispose();
  }
}

final class _RemoteCamera {
  _RemoteCamera(this.pipeline);

  final WatchedSessionPipeline pipeline;
  StreamSubscription<DecodedVideoFrame>? frames;
  DecodedVideoFrame? frame;

  /// The SSRC this sender's pictures arrive on, which is what a keyframe ask
  /// names.
  int? ssrc;
}
