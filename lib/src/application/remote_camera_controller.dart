import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_rtp_packet.dart';
import '../data/discord/discord_video_picture_receiver.dart';
import '../domain/video_decoder.dart';

/// Decrypts one whole picture for the room's group, for the sender named.
typedef CameraGroupDecryptor = Uint8List Function(
  String userId,
  Uint8List picture,
);

/// Everybody else's cameras in the voice room.
///
/// One receiver and one decoder per person, not one shared pair: two senders
/// interleave on the same socket, and a single receiver would splice one
/// person's packets into another's picture. The decoders are made through a
/// factory for the same reason the encoder is — a test host has no H.264
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
  }) : _packetsProvider = packetsProvider,
       _decoderFactory = decoderFactory,
       _groupDecryptorProvider = groupDecryptorProvider;

  final Stream<(String, DiscordRtpFrame)> Function() _packetsProvider;
  final VideoDecoderService Function() _decoderFactory;
  final CameraGroupDecryptor? Function()? _groupDecryptorProvider;

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
      final created = _RemoteCamera(decoder, decryptor: (picture) {
        final decryptor = _groupDecryptorProvider?.call();
        return decryptor == null ? picture : decryptor(userId, picture);
      });
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
    final unit = camera.receiver.accept(
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
  _RemoteCamera(this.decoder, {required VideoPictureGroupDecryptor decryptor})
    : receiver = DiscordVideoPictureReceiver(decryptor: decryptor);

  final VideoDecoderService decoder;

  /// Puts this sender's packets back into whole pictures, and decrypts each
  /// one once for the room's group.
  final DiscordVideoPictureReceiver receiver;
  StreamSubscription<DecodedVideoFrame>? subscription;
  DecodedVideoFrame? frame;
  int packets = 0;
}
