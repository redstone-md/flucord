import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/voice_audio.dart';
import '../domain/voice_connection.dart';
import '../domain/voice_media.dart';
import 'voice_audio_pipeline.dart';

enum VoiceState { idle, loading, ready, failure }

typedef VoiceSignalingServiceProvider = VoiceSignalingService? Function();

final class VoiceController extends ChangeNotifier {
  factory VoiceController(
    VoiceMediaService mediaService, {
    VoiceSignalingServiceProvider? signalingServiceProvider,
    VoiceOpusCodecFactory? audioCodecFactory,
    VoiceAudioPlaybackService? playbackService,
  }) => VoiceController._(
    mediaService,
    signalingServiceProvider ?? _noSignaling,
    audioCodecFactory,
    playbackService,
  );

  VoiceController._(
    this._mediaService,
    this._signalingServiceProvider,
    VoiceOpusCodecFactory? audioCodecFactory,
    this._playbackService,
  ) : _audioPipeline = audioCodecFactory == null
          ? null
          : VoiceAudioPipeline(
              mediaService: _mediaService,
              codecFactory: audioCodecFactory,
            ) {
    _screenEndedSubscription = _mediaService.screenShareEnded.listen((_) {
      _isScreenSharing = false;
      if (!_disposed) notifyListeners();
    });
    _audioErrorSubscription = _audioPipeline?.errors.listen((error) {
      _error = error;
      if (!_disposed) notifyListeners();
    });
    _remotePcmSubscription = _audioPipeline?.remotePcm.listen(_handleRemotePcm);
  }

  final VoiceMediaService _mediaService;
  final VoiceSignalingServiceProvider _signalingServiceProvider;
  final VoiceAudioPlaybackService? _playbackService;
  final VoiceAudioPipeline? _audioPipeline;
  StreamSubscription<void>? _screenEndedSubscription;
  StreamSubscription<Object>? _audioErrorSubscription;
  StreamSubscription<VoiceRemotePcmFrame>? _remotePcmSubscription;
  StreamSubscription<VoiceSignalingEvent>? _signalingSubscription;
  VoiceSignalingService? _signalingService;
  VoiceState _state = VoiceState.idle;
  VoiceConnectionStatus _connectionStatus = VoiceConnectionStatus.disconnected;
  List<VoiceDevice> _devices = const [];
  List<VoiceCaptureSource> _captureSources = const [];
  String? _selectedInputId;
  String? _selectedOutputId;
  String? _connectedGuildId;
  String? _connectedChannelId;
  VoiceTransportSession? _transportSession;
  Object? _error;
  bool _isMuted = false;
  bool _isScreenSharing = false;
  bool _isAudioPlaybackActive = false;
  bool _isBusy = false;
  bool _disposed = false;

  VoiceState get state => _state;
  VoiceConnectionStatus get connectionStatus => _connectionStatus;
  List<VoiceDevice> get inputDevices => _devices
      .where((device) => device.kind == VoiceDeviceKind.audioInput)
      .toList(growable: false);
  List<VoiceDevice> get outputDevices => _devices
      .where((device) => device.kind == VoiceDeviceKind.audioOutput)
      .toList(growable: false);
  List<VoiceCaptureSource> get captureSources => _captureSources;
  String? get selectedInputId => _selectedInputId;
  String? get selectedOutputId => _selectedOutputId;
  String? get connectedGuildId => _connectedGuildId;
  String? get connectedChannelId => _connectedChannelId;
  VoiceTransportSession? get transportSession => _transportSession;
  Object? get error => _error;
  bool get isConnected => _connectedChannelId != null;
  bool get hasDiscordSignaling => _signalingService != null;
  bool get isTransportReady => _transportSession != null;
  bool get isAudioUplinkActive => _audioPipeline?.isEnabled ?? false;
  bool get isAudioPlaybackActive => _isAudioPlaybackActive;
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
      await _playbackService?.initialize();
      final mediaDevices = await _mediaService.enumerateDevices();
      final playbackDevices = await _playbackService?.enumerateOutputDevices();
      _devices = playbackDevices == null
          ? mediaDevices
          : [
              ...mediaDevices.where(
                (device) => device.kind == VoiceDeviceKind.audioInput,
              ),
              ...playbackDevices,
            ];
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

  Future<void> connect({
    required String guildId,
    required String channelId,
  }) async {
    await initialize();
    if (_state != VoiceState.ready ||
        (_connectedGuildId == guildId && _connectedChannelId == channelId)) {
      return;
    }
    await _run(() async {
      final signalingService = _signalingServiceProvider();
      await _bindSignaling(signalingService);
      final previousGuildId = _connectedGuildId;
      if (previousGuildId != null && previousGuildId != guildId) {
        await _signalingService?.leaveVoiceChannel(previousGuildId);
      }
      if (_connectedChannelId == null) {
        await _mediaService.startMicrophone(_selectedInputId);
        await _mediaService.setMicrophoneEnabled(!_isMuted);
      }
      _connectedGuildId = guildId;
      _connectedChannelId = channelId;
      _transportSession = null;
      await _audioPipeline?.setEnabled(false);
      await _setPlaybackEnabled(false);
      if (signalingService != null) {
        _connectionStatus = VoiceConnectionStatus.joining;
        await signalingService.joinVoiceChannel(
          guildId: guildId,
          channelId: channelId,
          selfMute: _isMuted,
        );
      } else {
        _connectionStatus = VoiceConnectionStatus.disconnected;
      }
    });
  }

  Future<void> refreshSignalingService() async {
    final service = _signalingServiceProvider();
    if (identical(service, _signalingService)) return;
    await _run(() async {
      await _bindSignaling(service);
      final guildId = _connectedGuildId;
      final channelId = _connectedChannelId;
      if (service == null || guildId == null || channelId == null) return;
      _connectionStatus = VoiceConnectionStatus.joining;
      await service.joinVoiceChannel(
        guildId: guildId,
        channelId: channelId,
        selfMute: _isMuted,
      );
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
      final playbackService = _playbackService;
      if (playbackService == null) {
        await _mediaService.selectAudioOutput(deviceId);
      } else {
        await playbackService.selectOutput(deviceId);
      }
      _selectedOutputId = deviceId;
    });
  }

  Future<void> toggleMute() async {
    if (!isConnected) return;
    await _run(() async {
      _isMuted = !_isMuted;
      await _mediaService.setMicrophoneEnabled(!_isMuted);
      await _audioPipeline?.setEnabled(!_isMuted && isTransportReady);
      final guildId = _connectedGuildId;
      final channelId = _connectedChannelId;
      if (guildId != null && channelId != null) {
        await _signalingService?.joinVoiceChannel(
          guildId: guildId,
          channelId: channelId,
          selfMute: _isMuted,
        );
      }
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
      await _audioPipeline?.setEnabled(false);
      await _setPlaybackEnabled(false);
      final guildId = _connectedGuildId;
      if (guildId != null) {
        await _signalingService?.leaveVoiceChannel(guildId);
      }
      await _mediaService.stopScreenShare();
      await _mediaService.stopMicrophone();
      _connectedGuildId = null;
      _connectedChannelId = null;
      _connectionStatus = VoiceConnectionStatus.disconnected;
      _transportSession = null;
      _isScreenSharing = false;
      _isMuted = false;
    });
  }

  Future<void> _bindSignaling(VoiceSignalingService? service) async {
    if (identical(service, _signalingService)) return;
    await _signalingSubscription?.cancel();
    _signalingService = service;
    final audioTransport = service is VoiceAudioTransport
        ? service as VoiceAudioTransport
        : null;
    await _audioPipeline?.bindTransport(audioTransport);
    await _setPlaybackEnabled(false);
    _connectionStatus = VoiceConnectionStatus.disconnected;
    _transportSession = null;
    _signalingSubscription = service?.voiceEvents.listen(
      _handleSignalingEvent,
      onDone: _handleSignalingDone,
    );
  }

  void _handleSignalingEvent(VoiceSignalingEvent event) {
    switch (event) {
      case VoiceSignalingStatusEvent():
        _connectionStatus = event.status;
        if (event.error != null) _error = event.error;
        if (event.status == VoiceConnectionStatus.disconnected ||
            event.status == VoiceConnectionStatus.failure) {
          _transportSession = null;
          unawaited(_applyBackgroundAudioState(uplink: false, playback: false));
        }
      case VoiceTransportReadyEvent():
        _transportSession = event.session;
        unawaited(
          _applyBackgroundAudioState(uplink: !_isMuted, playback: true),
        );
      case VoiceCredentialsReadyEvent() ||
          VoiceDaveBinaryEvent() ||
          VoiceSpeakingEvent() ||
          VoiceUserDisconnectedEvent():
        break;
    }
    if (!_disposed) notifyListeners();
  }

  void _handleSignalingDone() {
    _signalingService = null;
    _connectionStatus = VoiceConnectionStatus.disconnected;
    _transportSession = null;
    unawaited(_unbindBackgroundAudio());
    if (!_disposed) notifyListeners();
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

  Future<void> _setPlaybackEnabled(bool enabled) async {
    final playbackService = _playbackService;
    if (playbackService == null) return;
    await playbackService.setEnabled(enabled);
    _isAudioPlaybackActive = enabled;
    if (!_disposed) notifyListeners();
  }

  Future<void> _applyBackgroundAudioState({
    required bool uplink,
    required bool playback,
  }) async {
    try {
      await _audioPipeline?.setEnabled(uplink);
      await _setPlaybackEnabled(playback);
    } catch (error) {
      _reportBackgroundError(error);
    }
  }

  Future<void> _unbindBackgroundAudio() async {
    try {
      await _audioPipeline?.bindTransport(null);
      await _setPlaybackEnabled(false);
    } catch (error) {
      _reportBackgroundError(error);
    }
  }

  void _reportBackgroundError(Object error) {
    _error = error;
    if (!_disposed) notifyListeners();
  }

  void _handleRemotePcm(VoiceRemotePcmFrame frame) {
    if (_disposed) return;
    try {
      _playbackService?.addPcmFrame(frame);
    } catch (error) {
      _reportBackgroundError(error);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_screenEndedSubscription?.cancel());
    unawaited(_audioErrorSubscription?.cancel());
    unawaited(_remotePcmSubscription?.cancel());
    unawaited(_signalingSubscription?.cancel());
    unawaited(_audioPipeline?.dispose());
    unawaited(_playbackService?.dispose());
    unawaited(_mediaService.dispose());
    super.dispose();
  }

  static VoiceSignalingService? _noSignaling() => null;
}
