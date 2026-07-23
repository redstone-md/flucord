import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../domain/voice_media.dart';

final class WebRtcVoiceMediaService implements VoiceMediaService {
  final RTCVideoRenderer _previewRenderer = RTCVideoRenderer();
  final StreamController<void> _screenShareEnded = StreamController.broadcast();
  MediaStream? _microphoneStream;
  MediaStream? _screenStream;
  bool _initialized = false;

  @override
  Object get previewRenderer => _previewRenderer;

  @override
  Stream<void> get screenShareEnded => _screenShareEnded.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _previewRenderer.initialize();
    _initialized = true;
  }

  @override
  Future<List<VoiceDevice>> enumerateDevices() async {
    final devices = await navigator.mediaDevices.enumerateDevices();
    return [
      for (final device in devices)
        if (device.kind == 'audioinput' || device.kind == 'audiooutput')
          VoiceDevice(
            id: device.deviceId,
            label: device.label.isEmpty ? 'Default device' : device.label,
            kind: device.kind == 'audioinput'
                ? VoiceDeviceKind.audioInput
                : VoiceDeviceKind.audioOutput,
          ),
    ];
  }

  @override
  Future<void> startMicrophone(String? deviceId) async {
    await stopMicrophone();
    _microphoneStream = await navigator.mediaDevices.getUserMedia({
      'audio': deviceId == null
          ? true
          : {
              'optional': [
                {'sourceId': deviceId},
              ],
              'echoCancellation': true,
              'noiseSuppression': true,
              'autoGainControl': true,
            },
      'video': false,
    });
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    for (final track in _microphoneStream?.getAudioTracks() ?? const []) {
      track.enabled = enabled;
    }
  }

  @override
  Future<void> selectAudioOutput(String deviceId) =>
      Helper.selectAudioOutput(deviceId);

  @override
  Future<List<VoiceCaptureSource>> enumerateCaptureSources() async {
    final sources = await desktopCapturer.getSources(
      types: const [SourceType.Screen, SourceType.Window],
      thumbnailSize: ThumbnailSize(320, 180),
    );
    return [
      for (final source in sources)
        VoiceCaptureSource(
          id: source.id,
          name: source.name,
          kind: source.type == SourceType.Screen
              ? VoiceCaptureKind.screen
              : VoiceCaptureKind.window,
          thumbnail: source.thumbnail,
        ),
    ];
  }

  @override
  Future<void> startScreenShare(String sourceId) async {
    await stopScreenShare();
    final stream = await navigator.mediaDevices.getDisplayMedia({
      'audio': false,
      'video': {
        'deviceId': {'exact': sourceId},
        'mandatory': {'frameRate': 30.0},
      },
    });
    _screenStream = stream;
    _previewRenderer.srcObject = stream;
    final tracks = stream.getVideoTracks();
    if (tracks.isNotEmpty) {
      tracks.first.onEnded = () => unawaited(_handleScreenShareEnded());
    }
  }

  Future<void> _handleScreenShareEnded() async {
    await stopScreenShare();
    if (!_screenShareEnded.isClosed) _screenShareEnded.add(null);
  }

  @override
  Future<void> stopMicrophone() async {
    await _stopStream(_microphoneStream);
    _microphoneStream = null;
  }

  @override
  Future<void> stopScreenShare() async {
    _previewRenderer.srcObject = null;
    for (final track in _screenStream?.getVideoTracks() ?? const []) {
      track.onEnded = null;
    }
    await _stopStream(_screenStream);
    _screenStream = null;
  }

  Future<void> _stopStream(MediaStream? stream) async {
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
  }

  @override
  Future<void> dispose() async {
    await stopScreenShare();
    await stopMicrophone();
    if (_initialized) await _previewRenderer.dispose();
    await _screenShareEnded.close();
  }
}
