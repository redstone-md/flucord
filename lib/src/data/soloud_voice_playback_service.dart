import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import '../domain/voice_audio.dart';
import '../domain/voice_media.dart';

final class SoLoudVoicePlaybackService implements VoiceAudioPlaybackService {
  static const int _sampleRate = 48000;
  static const int _channels = 2;
  static const double _bufferingSeconds = 0.06;

  final SoLoud _player = SoLoud.instance;
  final Map<String, AudioSource> _sources = {};
  bool _initialized = false;
  bool _enabled = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _player.init(
      sampleRate: _sampleRate,
      bufferSize: 960,
      channels: Channels.stereo,
      lowLatency: true,
    );
    _initialized = true;
  }

  @override
  Future<List<VoiceDevice>> enumerateOutputDevices() async {
    final devices = _player.listPlaybackDevices().toList(growable: false)
      ..sort((left, right) {
        if (left.isDefault == right.isDefault) {
          return left.name.compareTo(right.name);
        }
        return left.isDefault ? -1 : 1;
      });
    return [
      for (final device in devices)
        VoiceDevice(
          id: device.id.toString(),
          label: device.name,
          kind: VoiceDeviceKind.audioOutput,
        ),
    ];
  }

  @override
  Future<void> selectOutput(String deviceId) async {
    _requireInitialized();
    final id = int.tryParse(deviceId);
    final device = id == null
        ? null
        : _player
              .listPlaybackDevices()
              .where((item) => item.id == id)
              .firstOrNull;
    if (device == null) {
      throw StateError('Selected audio output is no longer available');
    }
    _player.changeDevice(newDevice: device);
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _requireInitialized();
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) await _disposeSources();
  }

  @override
  void addPcmFrame(VoiceRemotePcmFrame frame) {
    if (!_enabled || frame.samples.isEmpty) return;
    if (frame.samples.length % _channels != 0) {
      throw StateError('Remote PCM frame is not stereo aligned');
    }
    final source = _sources.putIfAbsent(frame.userId, _createSource);
    _player.addAudioDataStream(source, _asBytes(frame.samples));
  }

  AudioSource _createSource() {
    final source = _player.setBufferStream(
      maxBufferSizeDuration: const Duration(seconds: 5),
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: _bufferingSeconds,
      sampleRate: _sampleRate,
      channels: Channels.stereo,
      format: BufferType.s16le,
    );
    _player.play(source);
    return source;
  }

  Uint8List _asBytes(Int16List samples) => Uint8List.view(
    samples.buffer,
    samples.offsetInBytes,
    samples.lengthInBytes,
  );

  Future<void> _disposeSources() async {
    final sources = _sources.values.toList(growable: false);
    _sources.clear();
    for (final source in sources) {
      await _player.disposeSource(source);
    }
  }

  void _requireInitialized() {
    if (!_initialized) throw StateError('Voice playback is not initialized');
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    await setEnabled(false);
    _player.deinit();
    _initialized = false;
  }
}
