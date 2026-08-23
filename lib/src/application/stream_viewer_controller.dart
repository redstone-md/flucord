import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_h264_depacketizer.dart';
import '../domain/go_live_stream.dart';
import '../domain/video_decoder.dart';
import '../app_log.dart';

/// One RTP payload as it arrives from a stream connection.
final class IncomingVideoPacket {
  const IncomingVideoPacket({required this.payload, required this.marker});

  final Uint8List payload;

  /// Whether this payload ends a picture.
  final bool marker;
}

/// Watches somebody else's Go Live stream.
///
/// Three things in a row that were each built and none of which were joined:
/// packets arrive, the depacketiser turns them back into access units, and the
/// decoder turns those into pictures. Without this the viewer widget had
/// nothing to draw and the decoder nothing to decode.
final class StreamViewerController extends ChangeNotifier {
  StreamViewerController({
    required GoLiveRepository? Function() repositoryProvider,
    required VideoDecoderService decoder,
  }) : _repositoryProvider = repositoryProvider,
       _decoder = decoder;

  final GoLiveRepository? Function() _repositoryProvider;
  final VideoDecoderService _decoder;
  final DiscordH264Depacketizer _depacketizer = DiscordH264Depacketizer();

  StreamSubscription<IncomingVideoPacket>? _packets;
  GoLiveStreamKey? _watching;
  GoLiveStreamKey? _requested;
  int _receivedPackets = 0;
  int _decodedUnits = 0;
  Object? _error;
  bool _disposed = false;

  /// Whether this build can decode at all.
  bool get isSupported => _decoder.isSupported;

  /// Whose stream is being watched, or `null`.
  GoLiveStreamKey? get watching => _watching;

  /// Whose stream has been asked for but has not started arriving yet.
  ///
  /// Separate from [watching] because the two are seconds apart: the ask goes
  /// out on the main gateway, Discord answers with an endpoint, and only the
  /// connection that answer opens produces pictures. A button that waited for
  /// [watching] would look dead for the whole handshake.
  GoLiveStreamKey? get requested => _requested;

  /// Pictures for the viewer widget.
  Stream<DecodedVideoFrame> get frames => _decoder.frames;

  int get receivedPackets => _receivedPackets;

  /// How many access units came back out of the depacketiser, which is what
  /// separates "packets are arriving" from "pictures are arriving".
  int get decodedUnits => _decodedUnits;

  Object? get error => _error;

  /// Asks Discord to send [key]'s stream to this client.
  ///
  /// Nothing is decoded yet: this is the ask, and the endpoint it is answered
  /// with is what opens the connection the pictures cross.
  Future<bool> requestWatch(GoLiveStreamKey key) async {
    final repository = _repositoryProvider();
    if (repository == null || !_decoder.isSupported) return false;
    await stop();
    _error = null;
    _requested = key;
    _notify();
    try {
      await repository.watchStream(key);
      _diagnose('asked to watch ${key.userId}');
      return true;
    } on Object catch (error) {
      _error = error;
      _requested = null;
      _notify();
      return false;
    }
  }

  /// Starts decoding [packets] as [key], without asking Discord again.
  ///
  /// Used once the stream connection is up: the ask already went out, and
  /// repeating it would open a second one.
  Future<bool> attach(
    GoLiveStreamKey key, {
    required Stream<IncomingVideoPacket> packets,
  }) async {
    if (!_decoder.isSupported) return false;
    _error = null;
    try {
      await _decoder.start();
    } on Object catch (error) {
      _error = error;
      _notify();
      return false;
    }
    _watching = key;
    _requested = null;
    _depacketizer.reset();
    await _packets?.cancel();
    _packets = packets.listen(_accept, onError: _acceptError);
    _notify();
    return true;
  }

  /// Starts watching [key], reading packets from [packets].
  Future<bool> watch(
    GoLiveStreamKey key, {
    required Stream<IncomingVideoPacket> packets,
  }) async {
    final repository = _repositoryProvider();
    if (repository == null || !_decoder.isSupported) return false;
    await stop();
    _error = null;
    try {
      // Discord is told first: it does not send the picture to a client that
      // has not asked for it, so a decoder started before the ask would sit
      // idle and look broken.
      await repository.watchStream(key);
      await _decoder.start();
    } on Object catch (error) {
      _error = error;
      _notify();
      return false;
    }
    _watching = key;
    _depacketizer.reset();
    _packets = packets.listen(_accept, onError: _acceptError);
    _notify();
    return true;
  }

  Future<void> stop() async {
    final packets = _packets;
    _packets = null;
    _requested = null;
    await packets?.cancel();
    if (_watching == null) return;
    await _decoder.stop();
    _watching = null;
    _receivedPackets = 0;
    _decodedUnits = 0;
    _depacketizer.reset();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_packets?.cancel());
    _packets = null;
    unawaited(_decoder.stop());
    super.dispose();
  }

  void _diagnose(String what) {
    AppLog.warning('stream', what);
  }

  void _accept(IncomingVideoPacket packet) {
    // The first one is worth saying: it is the difference between a stream
    // that was asked for and one that is arriving.
    if (_receivedPackets == 0) {
      _diagnose('first packet from ${_watching?.userId}');
    }
    _receivedPackets++;
    final unit = _depacketizer.accept(packet.payload, marker: packet.marker);
    if (unit == null) return;
    _decodedUnits++;
    unawaited(_decoder.submit(unit));
    _notify();
  }

  void _acceptError(Object error) {
    _error = error;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
