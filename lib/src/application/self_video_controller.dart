import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/discord/discord_video_stream_transport.dart';
import '../data/discord/discord_voice_gateway_protocol.dart';
import '../domain/video_encoder.dart';
import '../domain/voice_audio.dart';

/// Sets `self_video` on the account's voice state and answers whether the
/// gateway took it.
typedef SelfVideoAnnouncer = Future<bool> Function({required bool enabled});

/// The account's own camera in the voice channel it is sitting in.
///
/// Deliberately apart from Go Live: a screen share is its own connection with
/// its own stream key and its own viewers, while a camera rides the voice
/// connection that is already open. The two share the encoder and the
/// packetiser and nothing above them.
///
/// Turning it on takes three announcements, and all three are needed. Opcode
/// 12 on the voice socket declares which SSRCs the pictures will arrive on;
/// opcode 4 on the main gateway sets `self_video` so every member list shows
/// the camera icon; and the RTP itself goes out on the voice socket that is
/// already carrying the audio. The first without the second sends pictures
/// nobody is told to expect, and the second without the first lights an icon
/// with nothing behind it.
final class SelfVideoController extends ChangeNotifier {
  SelfVideoController({
    required VideoEncoderService encoder,
    required VoiceVideoTransport? Function() transportProvider,
    required VideoFrameSink? Function() sinkProvider,
    required SelfVideoAnnouncer announceSelfVideo,
    VideoEncoderSettings settings = const VideoEncoderSettings.camera(),
  }) : _encoder = encoder,
       _transportProvider = transportProvider,
       _sinkProvider = sinkProvider,
       _announce = announceSelfVideo,
       _settings = settings;

  final VideoEncoderService _encoder;
  final VoiceVideoTransport? Function() _transportProvider;
  final VideoFrameSink? Function() _sinkProvider;
  final SelfVideoAnnouncer _announce;

  VideoEncoderSettings _settings;
  DiscordVideoStreamTransport? _transport;
  bool _isOn = false;
  bool _isBusy = false;
  Object? _error;

  /// Whether this build can encode at all. A machine with no camera still
  /// reports supported: [cameras] is simply empty and the button says so.
  bool get isSupported => _encoder.isSupported;

  /// The cameras attached, by name.
  List<String> get cameras => _encoder.cameraNames;

  /// Which camera the next start will use.
  int get selectedCamera => _settings.displayIndex;

  bool get isOn => _isOn;

  bool get isBusy => _isBusy;

  Object? get error => _error;

  /// How many RTP packets the picture has taken, which is what says the
  /// camera is moving rather than merely open.
  int get sentPackets => _transport?.sentPackets ?? 0;

  void selectCamera(int index) {
    if (index < 0 || index == _settings.displayIndex) return;
    _settings = VideoEncoderSettings.camera(
      displayIndex: index,
      width: _settings.width,
      height: _settings.height,
      framesPerSecond: _settings.framesPerSecond,
      bitrate: _settings.bitrate,
    );
    notifyListeners();
  }

  Future<bool> turnOn() async {
    if (_isOn || _isBusy) return _isOn;
    if (!_encoder.isSupported || cameras.isEmpty) {
      _fail(const VideoEncoderException(VideoEncoderFailure.noCamera));
      return false;
    }
    final transport = _transportProvider();
    final sink = _sinkProvider();
    final audioSsrc = transport?.audioSsrc;
    if (transport == null || sink == null || audioSsrc == null) {
      // Before the voice READY there is no SSRC to derive the video one from,
      // and pictures sent on a number the server allocated nothing for are
      // forwarded to nobody.
      _fail(StateError('The voice connection is not ready for a camera'));
      return false;
    }
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      await _encoder.start(_settings);
    } on Object catch (error) {
      _fail(error);
      return false;
    }
    // Declared before the first packet: a receiver that saw RTP on an
    // undeclared SSRC would drop it.
    transport.announceVideo(
      enabled: true,
      width: _settings.width,
      height: _settings.height,
      framesPerSecond: _settings.framesPerSecond,
      maxBitrate: _settings.bitrate,
    );
    _transport?.stop();
    _transport =
        DiscordVideoStreamTransport(
            ssrc: DiscordVoiceGatewayProtocol.videoSsrcFor(audioSsrc),
            sink: sink,
          )
          ..attach(_encoder.frames);
    if (!await _announce(enabled: true)) {
      await _tearDown(transport);
      _fail(StateError('The gateway would not take the camera'));
      return false;
    }
    _isOn = true;
    _isBusy = false;
    notifyListeners();
    return true;
  }

  Future<void> turnOff() async {
    if (!_isOn) return;
    _isBusy = true;
    notifyListeners();
    // Told first this time: a viewer still drawing the last picture of a
    // camera that already stopped is worse than one told a moment early.
    await _announce(enabled: false);
    await _tearDown(_transportProvider());
    _isOn = false;
    _isBusy = false;
    notifyListeners();
  }

  /// Turns the camera off without announcing anything.
  ///
  /// For a connection that has already gone: the socket that would carry the
  /// announcement is the one that dropped, and the server forgets the voice
  /// state with it.
  Future<void> forget() async {
    _transport?.stop();
    _transport = null;
    if (!_isOn) return;
    await _encoder.stop();
    _isOn = false;
    notifyListeners();
  }

  Future<bool> toggle() async {
    if (!_isOn) return turnOn();
    await turnOff();
    return false;
  }

  Future<void> _tearDown(VoiceVideoTransport? transport) async {
    transport?.announceVideo(enabled: false);
    _transport?.stop();
    _transport = null;
    await _encoder.stop();
  }

  void _fail(Object error) {
    _error = error;
    _isBusy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _transport?.stop();
    _transport = null;
    unawaited(_encoder.stop());
    super.dispose();
  }
}
