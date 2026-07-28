import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/voice_audio.dart';
import '../domain/voice_call.dart';
import '../domain/voice_connection.dart';
import '../domain/voice_media.dart';
import 'voice_audio_pipeline.dart';

enum VoiceState { idle, loading, ready, failure }

typedef VoiceSignalingServiceProvider = VoiceSignalingService? Function();
typedef DirectCallServiceProvider = DirectCallService? Function();

final class VoiceController extends ChangeNotifier {
  factory VoiceController(
    VoiceMediaService mediaService, {
    VoiceSignalingServiceProvider? signalingServiceProvider,
    DirectCallServiceProvider? callServiceProvider,
    VoiceOpusCodecFactory? audioCodecFactory,
    VoiceAudioPlaybackService? playbackService,
  }) => VoiceController._(
    mediaService,
    signalingServiceProvider ?? _noSignaling,
    callServiceProvider ?? _noCalls,
    audioCodecFactory,
    playbackService,
  );

  VoiceController._(
    this._mediaService,
    this._signalingServiceProvider,
    this._callServiceProvider,
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
  final DirectCallServiceProvider _callServiceProvider;
  final VoiceAudioPlaybackService? _playbackService;
  final VoiceAudioPipeline? _audioPipeline;
  StreamSubscription<void>? _screenEndedSubscription;
  StreamSubscription<Object>? _audioErrorSubscription;
  StreamSubscription<VoiceRemotePcmFrame>? _remotePcmSubscription;
  StreamSubscription<VoiceSignalingEvent>? _signalingSubscription;
  VoiceSignalingService? _signalingService;
  StreamSubscription<void>? _seatedSubscription;
  VoiceState _state = VoiceState.idle;
  VoiceConnectionStatus _connectionStatus = VoiceConnectionStatus.disconnected;
  List<VoiceDevice> _devices = const [];
  List<VoiceCaptureSource> _captureSources = const [];
  String? _selectedInputId;
  String? _selectedOutputId;
  String? _connectedGuildId;
  String? _connectedChannelId;
  bool _isCallSession = false;
  VoiceTransportSession? _transportSession;
  final Map<String, VoiceParticipant> _participants = {};
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
  List<VoiceParticipant> get participants =>
      List.unmodifiable(_participants.values);
  Object? get error => _error;
  bool get isConnected => _connectedChannelId != null;

  /// Whether the connection is a DM or group-DM call rather than guild voice.
  bool get isCallSession => _isCallSession;
  bool get hasDiscordSignaling => _signalingService != null;

  /// Who is seated in each voice channel, whether or not this client is in it.
  ///
  /// [participants] deliberately holds only the room we are connected to, so it
  /// cannot answer for the rest of the sidebar. This reads the transport's own
  /// view of every voice state instead.
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel =>
      _signalingService?.seatedByChannel ?? const {};
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

  Future<void> connect({required String guildId, required String channelId}) =>
      _connectTo(guildId: guildId, channelId: channelId, isCall: false);

  /// Joins a call in a DM or group DM.
  ///
  /// The media half is identical to guild voice — same microphone, same Opus
  /// uplink, same participant grid — so only the session's identity differs: a
  /// call has no guild and is addressed by its channel.
  Future<void> connectToCall({required String channelId}) =>
      _connectTo(guildId: null, channelId: channelId, isCall: true);

  Future<void> _connectTo({
    required String? guildId,
    required String channelId,
    required bool isCall,
  }) async {
    await initialize();
    if (_state != VoiceState.ready ||
        (_connectedGuildId == guildId &&
            _connectedChannelId == channelId &&
            _isCallSession == isCall)) {
      return;
    }
    await _run(() async {
      final signalingService = _signalingServiceProvider();
      await _bindSignaling(signalingService);
      // Walking between two channels of one guild is a move on the same
      // connection, so only a different session is torn down first. A call is
      // its own session, keyed by channel, and always is.
      final movedSession =
          _isCallSession != isCall ||
          (isCall
              ? _connectedChannelId != channelId
              : _connectedGuildId != guildId);
      if (movedSession) await _leaveActiveSession();
      if (_connectedChannelId == null) {
        await _mediaService.startMicrophone(_selectedInputId);
        await _mediaService.setMicrophoneEnabled(!_isMuted);
      }
      _connectedGuildId = guildId;
      _connectedChannelId = channelId;
      _isCallSession = isCall;
      _participants.clear();
      _transportSession = null;
      await _audioPipeline?.setEnabled(false);
      await _setPlaybackEnabled(false);
      _connectionStatus = VoiceConnectionStatus.joining;
      if (!await _sendJoin()) {
        _connectionStatus = VoiceConnectionStatus.disconnected;
      }
    });
  }

  /// Re-announces the current session, returning whether anything was sent.
  ///
  /// Both the join and every mute toggle go through here: R08's opcode 4 is a
  /// whole-state frame, so "mute" is simply the same join with a different
  /// flag, and a call sends it through the call plane instead of the guild one.
  Future<bool> _sendJoin() async {
    final channelId = _connectedChannelId;
    if (channelId == null) return false;
    if (_isCallSession) {
      final callService = _callServiceProvider();
      if (callService == null) return false;
      await callService.joinCall(channelId: channelId, selfMute: _isMuted);
      return true;
    }
    final guildId = _connectedGuildId;
    final signalingService = _signalingService;
    if (guildId == null || signalingService == null) return false;
    await signalingService.joinVoiceChannel(
      guildId: guildId,
      channelId: channelId,
      selfMute: _isMuted,
    );
    return true;
  }

  Future<void> _leaveActiveSession() async {
    final channelId = _connectedChannelId;
    if (channelId == null) return;
    if (_isCallSession) {
      await _callServiceProvider()?.leaveCall(channelId);
      return;
    }
    final guildId = _connectedGuildId;
    if (guildId != null) await _signalingService?.leaveVoiceChannel(guildId);
  }

  Future<void> refreshSignalingService() async {
    final service = _signalingServiceProvider();
    if (identical(service, _signalingService)) return;
    await _run(() async {
      await _bindSignaling(service);
      if (service == null || _connectedChannelId == null) return;
      _connectionStatus = VoiceConnectionStatus.joining;
      await _sendJoin();
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
      await _sendJoin();
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
      await _leaveActiveSession();
      await _mediaService.stopScreenShare();
      await _mediaService.stopMicrophone();
      _connectedGuildId = null;
      _connectedChannelId = null;
      _isCallSession = false;
      _connectionStatus = VoiceConnectionStatus.disconnected;
      _transportSession = null;
      _participants.clear();
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
    _participants.clear();
    // The sidebar renders seats for channels this client is not in, so it has
    // to rebuild on any voice state the transport sees, not only on the events
    // that belong to the room we joined.
    unawaited(_seatedSubscription?.cancel());
    _seatedSubscription = service?.seatedChanges.listen((_) {
      if (!_disposed) notifyListeners();
    });
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
          _participants.clear();
          unawaited(_applyBackgroundAudioState(uplink: false, playback: false));
        }
      case VoiceTransportReadyEvent():
        _transportSession = event.session;
        unawaited(
          _applyBackgroundAudioState(uplink: !_isMuted, playback: true),
        );
      case VoiceCredentialsReadyEvent():
        _participants.putIfAbsent(
          event.credentials.userId,
          () => VoiceParticipant(userId: event.credentials.userId),
        );
      case VoiceParticipantStateEvent():
        _applyParticipantState(event);
      case VoiceSpeakingEvent():
        final participant =
            _participants[event.userId] ??
            VoiceParticipant(userId: event.userId);
        _participants[event.userId] = participant.copyWith(
          ssrc: event.ssrc,
          speakingFlags: event.speakingFlags,
        );
      case VoiceUserDisconnectedEvent():
        _participants.remove(event.userId);
      case VoiceDaveBinaryEvent():
        break;
    }
    if (!_disposed) notifyListeners();
  }

  void _handleSignalingDone() {
    _signalingService = null;
    _connectionStatus = VoiceConnectionStatus.disconnected;
    _transportSession = null;
    _participants.clear();
    unawaited(_unbindBackgroundAudio());
    if (!_disposed) notifyListeners();
  }

  void _applyParticipantState(VoiceParticipantStateEvent event) {
    if (event.guildId != _connectedGuildId ||
        event.channelId != _connectedChannelId) {
      _participants.remove(event.userId);
      return;
    }
    final participant =
        _participants[event.userId] ?? VoiceParticipant(userId: event.userId);
    _participants[event.userId] = participant.copyWith(
      selfMuted: event.selfMuted,
      selfDeafened: event.selfDeafened,
      serverMuted: event.serverMuted,
      serverDeafened: event.serverDeafened,
      isStreaming: event.isStreaming,
      isVideoEnabled: event.isVideoEnabled,
    );
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
    unawaited(_seatedSubscription?.cancel());
    unawaited(_audioPipeline?.dispose());
    unawaited(_playbackService?.dispose());
    unawaited(_mediaService.dispose());
    super.dispose();
  }

  static VoiceSignalingService? _noSignaling() => null;

  static DirectCallService? _noCalls() => null;
}
