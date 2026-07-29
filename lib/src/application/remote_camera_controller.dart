import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_h264_depacketizer.dart';
import '../data/discord/discord_rtp_packet.dart';
import '../domain/video_decoder.dart';

/// Everybody else's cameras in the voice room.
///
/// One depacketiser and one decoder per person, not one shared pair: two
/// senders interleave on the same socket, and a single depacketiser would
/// splice one person's fragments into another's picture. The decoders are made
/// through a factory for the same reason the encoder is — a test host has no
/// H.264 decoder, and the controller has to be exercisable without one.
final class RemoteCameraController extends ChangeNotifier {
  RemoteCameraController({
    required Stream<(String, DiscordRtpFrame)> Function() packetsProvider,
    required VideoDecoderService Function() decoderFactory,
  }) : _packetsProvider = packetsProvider,
       _decoderFactory = decoderFactory;

  final Stream<(String, DiscordRtpFrame)> Function() _packetsProvider;
  final VideoDecoderService Function() _decoderFactory;

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
  int packetsFrom(String userId) => _cameras[userId]?.packets ?? 0;

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
    final camera = _cameras.putIfAbsent(userId, () {
      final decoder = _decoderFactory();
      final created = _RemoteCamera(decoder);
      // Started lazily: a room where nobody turns a camera on should not open
      // a decoder per participant.
      created.subscription = decoder.frames.listen((picture) {
        created.frame = picture;
        _notify();
      });
      unawaited(decoder.start());
      return created;
    });
    camera.packets++;
    final unit = camera.depacketizer.accept(
      Uint8List.fromList(frame.payload),
      marker: frame.header.marker,
    );
    if (unit == null) return;
    unawaited(camera.decoder.submit(unit));
  }

  void _clearCameras() {
    for (final camera in _cameras.values) {
      unawaited(camera.subscription?.cancel());
      unawaited(camera.decoder.stop());
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
  _RemoteCamera(this.decoder);

  final VideoDecoderService decoder;
  final DiscordH264Depacketizer depacketizer = DiscordH264Depacketizer();
  StreamSubscription<DecodedVideoFrame>? subscription;
  DecodedVideoFrame? frame;
  int packets = 0;
}
