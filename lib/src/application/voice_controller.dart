import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/voice_media.dart';

enum VoiceState { idle, loading, ready, failure }

final class VoiceController extends ChangeNotifier {
  VoiceController(this._mediaService) {
    _screenEndedSubscription = _mediaService.screenShareEnded.listen((_) {
      _isScreenSharing = false;
      if (!_disposed) notifyListeners();
    });
  }

  final VoiceMediaService _mediaService;
  StreamSubscription<void>? _screenEndedSubscription;
  VoiceState _state = VoiceState.idle;
  List<VoiceDevice> _devices = const [];
  List<VoiceCaptureSource> _captureSources = const [];
  String? _selectedInputId;
  String? _selectedOutputId;
  String? _connectedChannelId;
  Object? _error;
  bool _isMuted = false;
  bool _isScreenSharing = false;
  bool _isBusy = false;
  bool _disposed = false;

  VoiceState get state => _state;
  List<VoiceDevice> get inputDevices => _devices
      .where((device) => device.kind == VoiceDeviceKind.audioInput)
      .toList(growable: false);
  List<VoiceDevice> get outputDevices => _devices
      .where((device) => device.kind == VoiceDeviceKind.audioOutput)
      .toList(growable: false);
  List<VoiceCaptureSource> get captureSources => _captureSources;
  String? get selectedInputId => _selectedInputId;
  String? get selectedOutputId => _selectedOutputId;
  String? get connectedChannelId => _connectedChannelId;
  Object? get error => _error;
  bool get isConnected => _connectedChannelId != null;
  bool get isMuted => _isMuted;
  bool get isScreenSharing => _isScreenSharing;
  bool get isBusy => _isBusy;
  Object? get previewRenderer => _mediaService.previewRenderer;

  Future<void> initialize() async {
    if (_state != VoiceState.idle) return;
    _state = VoiceState.loading;
    notifyListeners();
    try {
      await _mediaService.initialize();
      _devices = await _mediaService.enumerateDevices();
      _selectedInputId = _firstDeviceId(VoiceDeviceKind.audioInput);
      _selectedOutputId = _firstDeviceId(VoiceDeviceKind.audioOutput);
      _state = VoiceState.ready;
    } catch (error) {
      _error = error;
      _state = VoiceState.failure;
    }
    if (!_disposed) notifyListeners();
  }

  String? _firstDeviceId(VoiceDeviceKind kind) {
    for (final device in _devices) {
      if (device.kind == kind) return device.id;
    }
    return null;
  }

  Future<void> connect(String channelId) async {
    await initialize();
    if (_state != VoiceState.ready || _connectedChannelId == channelId) return;
    await _run(() async {
      if (_connectedChannelId == null) {
        await _mediaService.startMicrophone(_selectedInputId);
        await _mediaService.setMicrophoneEnabled(!_isMuted);
      }
      _connectedChannelId = channelId;
    });
  }

  Future<void> selectInput(String deviceId) async {
    if (_selectedInputId == deviceId) return;
    await _run(() async {
      _selectedInputId = deviceId;
      if (isConnected) {
        await _mediaService.startMicrophone(deviceId);
        await _mediaService.setMicrophoneEnabled(!_isMuted);
      }
    });
  }

  Future<void> selectOutput(String deviceId) async {
    if (_selectedOutputId == deviceId) return;
    await _run(() async {
      await _mediaService.selectAudioOutput(deviceId);
      _selectedOutputId = deviceId;
    });
  }

  Future<void> toggleMute() async {
    if (!isConnected) return;
    await _run(() async {
      _isMuted = !_isMuted;
      await _mediaService.setMicrophoneEnabled(!_isMuted);
    });
  }

  Future<void> loadCaptureSources() async {
    await _run(() async {
      _captureSources = await _mediaService.enumerateCaptureSources();
    });
  }

  Future<void> shareScreen(String sourceId) async {
    await _run(() async {
      await _mediaService.startScreenShare(sourceId);
      _isScreenSharing = true;
    });
  }

  Future<void> stopScreenShare() async {
    await _run(() async {
      await _mediaService.stopScreenShare();
      _isScreenSharing = false;
    });
  }

  Future<void> disconnect() async {
    await _run(() async {
      await _mediaService.stopScreenShare();
      await _mediaService.stopMicrophone();
      _connectedChannelId = null;
      _isScreenSharing = false;
      _isMuted = false;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_isBusy) return;
    _isBusy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _error = error;
    } finally {
      _isBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_screenEndedSubscription?.cancel());
    unawaited(_mediaService.dispose());
    super.dispose();
  }
}
