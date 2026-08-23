import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:record/record.dart';

import '../domain/voice_media.dart';

/// Microphone capture and speaker selection through WebRTC's device layer.
///
/// Audio only: video capture lives in the capture and encode module
/// (`VideoCaptureHub`), which is the machine's one path to a display.
final class WebRtcVoiceMediaService implements VoiceMediaService {
  static const int _sampleRate = 48000;
  static const int _channels = 2;

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<VoicePcmChunk> _microphonePcm =
      StreamController.broadcast();
  StreamSubscription<Uint8List>? _microphoneSubscription;
  bool _initialized = false;
  bool _microphoneEnabled = true;

  @override
  Stream<VoicePcmChunk> get microphonePcm => _microphonePcm.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
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
  Future<void> stopMicrophone() async {
    if (await _recorder.isRecording()) await _recorder.stop();
    await _microphoneSubscription?.cancel();
    _microphoneSubscription = null;
  }

  @override
  Future<void> dispose() async {
    await stopMicrophone();
    await _recorder.dispose();
    await _microphonePcm.close();
  }
}
