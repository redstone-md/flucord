import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:record/record.dart';

import '../domain/voice_media.dart';

final class WebRtcVoiceMediaService implements VoiceMediaService {
  static const int _sampleRate = 48000;
  static const int _channels = 2;

  final RTCVideoRenderer _previewRenderer = RTCVideoRenderer();
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<VoicePcmChunk> _microphonePcm =
      StreamController.broadcast();
  final StreamController<void> _screenShareEnded = StreamController.broadcast();
  StreamSubscription<Uint8List>? _microphoneSubscription;
  MediaStream? _screenStream;
  bool _initialized = false;
  bool _microphoneEnabled = true;

  @override
  Object get previewRenderer => _previewRenderer;

  @override
  Stream<VoicePcmChunk> get microphonePcm => _microphonePcm.stream;

  @override
  Stream<void> get screenShareEnded => _screenShareEnded.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _previewRenderer.initialize();
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission was denied');
    }
    _initialized = true;
  }

  @override
  Future<List<VoiceDevice>> enumerateDevices() async {
    final inputs = await _recorder.listInputDevices();
    final devices = await navigator.mediaDevices.enumerateDevices();
    return [
      for (final device in inputs)
        VoiceDevice(
          id: device.id,
          label: device.label.isEmpty ? 'Default microphone' : device.label,
          kind: VoiceDeviceKind.audioInput,
        ),
      for (final device in devices)
        if (device.kind == 'audiooutput')
          VoiceDevice(
            id: device.deviceId,
            label: device.label.isEmpty ? 'Default device' : device.label,
            kind: VoiceDeviceKind.audioOutput,
          ),
    ];
  }

  @override
  Future<void> startMicrophone(String? deviceId) async {
    await stopMicrophone();
    if (!await _recorder.hasPermission()) {
      throw StateError('Microphone permission was denied');
    }
    final devices = await _recorder.listInputDevices();
    final selected = deviceId == null
        ? null
        : devices.where((device) => device.id == deviceId).firstOrNull;
    if (deviceId != null && selected == null) {
      throw StateError('Selected microphone is no longer available');
    }
    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: _channels,
        device: selected,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _microphoneSubscription = stream.listen(
      _handleMicrophoneBytes,
      onError: _microphonePcm.addError,
    );
  }

  void _handleMicrophoneBytes(Uint8List bytes) {
    if (!_microphoneEnabled || bytes.isEmpty || _microphonePcm.isClosed) return;
    _microphonePcm.add(
      VoicePcmChunk(bytes: bytes, sampleRate: _sampleRate, channels: _channels),
    );
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    _microphoneEnabled = enabled;
  }

  @override
  Future<void> selectAudioOutput(String deviceId) =>
      Helper.selectAudioOutput(deviceId);

  @override
  Future<List<VoiceCaptureSource>> enumerateCaptureSources() async {
    final sources = await _currentSources(thumbnails: true);
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

  /// The capture sources as they are right now.
  ///
  /// Re-enumerated rather than remembered. The capturer's list is a snapshot:
  /// a display that slept, a window that closed, or a monitor unplugged since
  /// the last read leaves handles behind that fail with "that display is no
  /// longer attached" when they are used.
  Future<List<DesktopCapturerSource>> _currentSources({
    bool thumbnails = false,
  }) async {
    const types = [SourceType.Screen, SourceType.Window];
    await desktopCapturer.updateSources(types: types);
    return desktopCapturer.getSources(
      types: types,
      thumbnailSize: thumbnails ? ThumbnailSize(320, 180) : ThumbnailSize(1, 1),
    );
  }

  @override
  Future<void> startScreenShare(String? sourceId) async {
    await stopScreenShare();
    // Windows will not capture without being told what to capture: an absent
    // deviceId is answered with "source not found". So the primary screen is
    // resolved here, against a list read at the moment of the share rather
    // than whenever the picker last ran.
    final source = sourceId ?? await _primaryScreenId();
    final stream = await navigator.mediaDevices.getDisplayMedia({
      'audio': false,
      'video': {
        'deviceId': {'exact': source},
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

  Future<String> _primaryScreenId() async {
    final sources = await _currentSources();
    final screen = sources
        .where((source) => source.type == SourceType.Screen)
        .firstOrNull;
    // Windows are deliberately not a fallback: sharing whatever window
    // enumerated first is worse than saying there is nothing to share.
    if (screen == null) {
      throw StateError('This machine reported no screen to capture');
    }
    return screen.id;
  }

  Future<void> _handleScreenShareEnded() async {
    await stopScreenShare();
    if (!_screenShareEnded.isClosed) _screenShareEnded.add(null);
  }

  @override
  Future<void> stopMicrophone() async {
    if (await _recorder.isRecording()) await _recorder.stop();
    await _microphoneSubscription?.cancel();
    _microphoneSubscription = null;
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
    await _recorder.dispose();
    await _microphonePcm.close();
    await _screenShareEnded.close();
  }
}
