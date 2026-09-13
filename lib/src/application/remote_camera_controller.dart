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
///
/// A camera is released when its sender is gone ([forget]) or when the window
/// cannot be seen ([setSuspended], ADR-0003): packets are still counted, but
/// the decoder is only open while its pictures can be drawn.
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

  /// Whether decoding is held back because the window cannot be seen. Set
  /// before the first camera opens, so a room joined from the tray opens no
  /// decoders at all.
  bool _suspended = false;
  bool _disposed = false;

  /// Who is currently sending a picture this client has drawn at least once.
  List<String> get senders => [
    for (final entry in _cameras.entries)
      if (entry.value.frame != null) entry.key,
  ];

  /// The latest picture from [userId], or `null` if none has decoded yet.
  DecodedVideoFrame? frameFor(String userId) => _cameras[userId]?.frame;

  /// The live pictures from [userId], for a tile that follows them itself.
  /// Null while this client holds no camera for them. This is the road the
  /// pictures travel once their tile exists: announcing each one through
  /// [notifyListeners] rebuilt the whole conversation pane, timeline
  /// included, at the camera's frame rate.
  Stream<DecodedVideoFrame>? framesFor(String userId) =>
      _cameras[userId]?.pipeline.frames;

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

  /// Whether decoding is being held back because the window cannot be seen.
  bool get isSuspended => _suspended;

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
      final first = camera.frame == null;
      camera.frame = picture;
      // One announcement, when the tile appears. The rest of the pictures go
      // to that tile alone, through [framesFor].
      if (first) _notify();
    });
    // Suspended cameras keep counting packets and open their decoder when
    // the window comes back (ADR-0003).
    if (!_suspended) _setDecoding(userId, camera, on: true);
    return camera;
  }

  /// Opens or lets go of one camera's decoder. A decoder that will not open
  /// is logged, and the camera keeps counting packets for the next attempt.
  void _setDecoding(String userId, _RemoteCamera camera, {required bool on}) {
    unawaited(
      camera.pipeline.setDecoding(on).catchError(
        (Object error) =>
            AppLog.warning('camera', 'decoder failed for $userId: $error'),
      ),
    );
  }

  /// Releases one sender's camera: their decoder stops and their last
  /// decoded picture goes with it. A no-op for a sender this client holds no
  /// camera for.
  void forget(String userId) {
    final camera = _cameras.remove(userId);
    if (camera == null) return;
    _close(camera);
    _notify();
  }

  /// Holds decoding back, or lets it run: the window left the screen, or
  /// came back (ADR-0003). Releasing lets go of every decoder; resuming
  /// opens them on the next keyframe, so a half picture from before the
  /// window went away is never decoded.
  void setSuspended(bool suspended) {
    if (_suspended == suspended) return;
    _suspended = suspended;
    for (final entry in _cameras.entries) {
      _setDecoding(entry.key, entry.value, on: !suspended);
    }
  }

  void _askForKeyframe(String userId) {
    final ssrc = _cameras[userId]?.ssrc;
    if (ssrc != null) _requestKeyframe?.call(ssrc);
  }

  void _close(_RemoteCamera camera) {
    unawaited(camera.frames?.cancel());
    unawaited(camera.pipeline.close());
  }

  void _clearCameras() {
    for (final camera in _cameras.values) {
      _close(camera);
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
