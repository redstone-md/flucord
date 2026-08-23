import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/voice_audio.dart';
import '../domain/voice_call.dart';
import '../domain/voice_connection.dart';
import '../domain/voice_media.dart';
import 'voice_audio_pipeline.dart';

part 'voice_controller_devices.dart';

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
  StreamSubscription<Object>? _audioErrorSubscription;
  StreamSubscription<VoiceRemotePcmFrame>? _remotePcmSubscription;
  StreamSubscription<VoiceSignalingEvent>? _signalingSubscription;
  VoiceSignalingService? _signalingService;
  StreamSubscription<void>? _seatedSubscription;
  VoiceState _state = VoiceState.idle;
  VoiceConnectionStatus _connectionStatus = VoiceConnectionStatus.disconnected;
  List<VoiceDevice> _devices = const [];
  String? _selectedInputId;
  String? _selectedOutputId;
  String? _connectedGuildId;
  String? _connectedChannelId;
  bool _isCallSession = false;
  VoiceTransportSession? _transportSession;
  final Map<String, VoiceParticipant> _participants = {};
  Object? _error;

  /// Why the audio devices could not be opened, kept apart from [_error] so
  /// a transport failure is not reported as a missing microphone.
  Object? _deviceError;
  Object? _microphoneError;
  bool _isMuted = false;
  bool _isDeafened = false;
  bool _isCameraOn = false;
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
  String? get selectedInputId => _selectedInputId;
  String? get selectedOutputId => _selectedOutputId;
  String? get connectedGuildId => _connectedGuildId;
  String? get connectedChannelId => _connectedChannelId;
  VoiceTransportSession? get transportSession => _transportSession;

  /// Who is in the room on screen.
  ///
  /// Built from the roster of who is seated rather than from the events this
  /// connection happened to see. The events are announcements — somebody
  /// arrived, somebody spoke — and a client that has just reconnected, or
  /// re-entered a channel it was already in, is sent none of them for the
  /// people who were already there. The room rendered empty while four people
  /// were plainly listed in the sidebar.
  ///
  /// What the connection knows is still layered on top: speaking flags and
  /// SSRCs only ever come from the transport.
  List<VoiceParticipant> get participants {
    final channelId = _connectedChannelId;
    if (channelId == null) return List.unmodifiable(_participants.values);
    final seated = _signalingService?.seatedByChannel[channelId] ?? const [];
    final byUser = <String, VoiceParticipant>{};
    for (final state in seated) {
      final known = _participants[state.userId];
      byUser[state.userId] = (known ?? VoiceParticipant(userId: state.userId))
          .copyWith(
            selfMuted: state.selfMuted,
            selfDeafened: state.selfDeafened,
            serverMuted: state.serverMuted,
            serverDeafened: state.serverDeafened,
            isStreaming: state.isStreaming,
            isVideoEnabled: state.isVideoEnabled,
          );
    }
    // Anybody the transport knows about but the roster has not caught up on
    // yet — a join announced on the voice socket first — is still shown.
    for (final entry in _participants.entries) {
      byUser.putIfAbsent(entry.key, () => entry.value);
    }
    return List.unmodifiable(byUser.values);
  }

  Object? get error => _error;

  /// Why the microphone could not be opened, or `null` when it is running.
  ///
  /// Separate from [error] because it is not a failure to join: the room is
  /// connected and audible, the uplink simply has nothing to send.
  Object? get microphoneError => _microphoneError;

  /// Why the audio devices could not be opened, or null.
  Object? get deviceError => _deviceError;

  /// Why joining a voice channel is not possible at all, or `null`.
  ///
  /// Answered before a join is attempted so the room can say what is missing
  /// instead of showing "Disconnected" with no reason.
  String? get joinBlockedReason {
    if (_state == VoiceState.failure && _signalingService == null) {
      return 'Audio devices could not be opened, and this session has no '
          'Discord voice transport.';
    }
    if (!hasDiscordSignaling && _signalingServiceProvider() == null) {
      return 'This session cannot reach Discord voice. Sign in with a Discord '
          'account to join voice channels.';
    }
    return null;
  }

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

  /// Whether this account has silenced the room for itself.
  bool get isDeafened => _isDeafened;

  /// Whether this account's camera is announced to the room.
  ///
  /// Held here rather than on the camera controller because opcode 4 is a
  /// whole-state frame: the flag has to be replayed with every mute toggle and
  /// every reconnect, and the thing that replays those is this.
  bool get isCameraOn => _isCameraOn;
  bool get isBusy => _isBusy;

  Future<void> initialize() async {
    // A previous failure is tried again rather than remembered forever. Audio
    // devices come and go — a headset is plugged in, an exclusive-mode
    // application lets go — and the old behaviour left a client that failed
    // once with no devices for the rest of the session, showing the first
    // error over every later attempt.
    if (_state == VoiceState.loading || _state == VoiceState.ready) return;
    _state = VoiceState.loading;
    _error = null;
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
      _deviceError = error;
      _state = VoiceState.failure;
    }
    if (!_disposed) notifyListeners();
  }

  /// Opens the audio devices again after a failure.
  ///
  /// Its own entry point so a surface can offer the retry: walking out of the
  /// channel and back in is not an obvious way to ask for one, and it is what
  /// somebody had to do before.
  Future<void> retryDevices() async {
    if (_state == VoiceState.loading) return;
    _state = VoiceState.idle;
    _deviceError = null;
    await initialize();
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
    if (_connectedGuildId == guildId &&
        _connectedChannelId == channelId &&
        _isCallSession == isCall) {
      return;
    }
    // A machine with no working capture device must still be able to walk into
    // a channel and listen, which is what Discord does. Refusing the join
    // outright — the old behaviour — left the room showing "Disconnected" with
    // nothing said about why, and no way to hear anybody.
    if (_state == VoiceState.loading) return;
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
        // Failing to open the microphone must not abort the join: the room is
        // still worth being in to listen. The reason is kept so the room can
        // say the uplink is off rather than leaving a silent mic looking fine.
        try {
          await _mediaService.startMicrophone(_selectedInputId);
          await _mediaService.setMicrophoneEnabled(!_isMuted);
          _microphoneError = null;
        } on Object catch (error) {
          _microphoneError = error;
        }
      }
      _connectedGuildId = guildId;
      _connectedChannelId = channelId;
      _isCallSession = isCall;
      _participants.clear();
      _transportSession = null;
      await _audioPipeline?.setEnabled(false);
      await _setPlaybackEnabled(false);
      // Only a session that is actually being established says "joining". A
      // transport already up for this channel — a rebind, or a second call
      // into the same room — keeps what it has, or the room announces a
      // connection it never lost.
      if (movedSession ||
          signalingService?.currentStatus != VoiceConnectionStatus.ready) {
        _connectionStatus = VoiceConnectionStatus.joining;
        _logStatus('joining', _connectionStatus);
      }
      if (!await _sendJoin()) {
        _connectionStatus = VoiceConnectionStatus.disconnected;
        _logStatus('join not sent', _connectionStatus);
      }
    });
  }

  /// Sets the camera flag and re-announces the session with it.
  ///
  /// Answers whether the room was told. A camera turned on while nothing is
  /// connected is refused rather than remembered: the flag would then be
  /// replayed into whatever channel is joined next.
  Future<bool> setCameraAnnounced({required bool enabled}) async {
    if (_connectedChannelId == null) return false;
    if (_isCameraOn == enabled) return true;
    _isCameraOn = enabled;
    final sent = await _sendJoin();
    if (!sent) _isCameraOn = !enabled;
    if (!_disposed) notifyListeners();
    return sent;
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
      await callService.joinCall(
        channelId: channelId,
        selfMute: _isMuted,
        selfDeaf: _isDeafened,
        selfVideo: _isCameraOn,
      );
      return true;
    }
    final guildId = _connectedGuildId;
    final signalingService = _signalingService;
    if (guildId == null || signalingService == null) return false;
    await signalingService.joinVoiceChannel(
      guildId: guildId,
      channelId: channelId,
      selfMute: _isMuted,
      selfDeaf: _isDeafened,
      selfVideo: _isCameraOn,
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
      if (service.currentStatus != VoiceConnectionStatus.ready) {
        _connectionStatus = VoiceConnectionStatus.joining;
        _logStatus('joining', _connectionStatus);
      }
      await _sendJoin();
    });
  }

  Future<void> disconnect() async {
    await _run(() async {
      await _audioPipeline?.setEnabled(false);
      await _setPlaybackEnabled(false);
      await _leaveActiveSession();
      await _mediaService.stopMicrophone();
      _connectedGuildId = null;
      _connectedChannelId = null;
      _isCallSession = false;
      _connectionStatus = VoiceConnectionStatus.disconnected;
      _transportSession = null;
      _participants.clear();
      _isMuted = false;
      _isDeafened = false;
      _isCameraOn = false;
    });
  }

  Future<void> _bindSignaling(VoiceSignalingService? service) async {
    // A service that is already bound *and listened to* is left alone. The
    // second half of that matters: a bind that failed part way used to leave
    // the service set with no subscription behind it, and every bind after it
    // took this early exit — so the transport ran, carried audio, and the
    // controller never heard a word of it. The room said "joining" for the
    // whole call.
    if (identical(service, _signalingService) &&
        (service == null || _signalingSubscription != null)) {
      return;
    }
    await _signalingSubscription?.cancel();
    _signalingService = service;
    // Subscribed before anything that can throw. Sound is what a room can
    // survive losing; hearing the transport is not.
    unawaited(_seatedSubscription?.cancel());
    _seatedSubscription = service?.seatedChanges.listen((_) {
      if (!_disposed) notifyListeners();
    });
    _signalingSubscription = service?.voiceEvents.listen(
      _handleSignalingEvent,
      onDone: _handleSignalingDone,
    );
    // Read rather than waited for. Binding to a service that is already
    // connected used to reset the status to disconnected and then sit there:
    // the `ready` it was waiting for had already been announced, and nothing
    // announces it twice, so a working call showed as joining forever.
    _connectionStatus =
        service?.currentStatus ?? VoiceConnectionStatus.disconnected;
    _logStatus('bound', _connectionStatus);
    _transportSession = service?.currentSession;
    _participants.clear();
    final audioTransport = service is VoiceAudioTransport
        ? service as VoiceAudioTransport
        : null;
    try {
      await _audioPipeline?.bindTransport(audioTransport);
      await _setPlaybackEnabled(false);
    } on Object catch (error) {
      // A playback device that will not open is worth reporting and worth
      // surviving: the room is still joined and everything else still works.
      _error = error;
      _logStatus('audio bind failed', _connectionStatus, error: error);
    }
  }

  void _handleSignalingEvent(VoiceSignalingEvent event) {
    switch (event) {
      case VoiceSignalingStatusEvent():
        // A room that shows the wrong status is unfalsifiable without this:
        // the transport can be carrying audio while the label says joining,
        // and nothing else records which side lost the transition. Statuses
        // only — no channel, no session, nothing about who is in the room.
        _logStatus('signalled', event.status, error: event.error);
        _connectionStatus = event.status;
        // A reconnect is not a problem to report. The status line already says
        // "Reconnecting", and putting the close code underneath it in red said
        // the same thing twice — the second time as though something needed
        // doing about it.
        if (event.error != null &&
            event.status != VoiceConnectionStatus.reconnecting) {
          _error = event.error;
        }
        // A connection that came back clears what killed the last one. The
        // room used to keep showing a close code in red over a working
        // call, because nothing ever took the message down.
        if (event.status == VoiceConnectionStatus.ready ||
            event.status == VoiceConnectionStatus.reconnecting) {
          _error = null;
        }
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

  void _logStatus(String what, VoiceConnectionStatus status, {Object? error}) {
    final line =
        'flucord.voice.status $what: ${status.name}'
        '${error == null ? '' : ' ($error)'}';
    developer.log(line, name: 'flucord.voice.status');
    // Straight to stdout, not `debugPrint`: `dart:developer` writes to the VM
    // service, which a desktop build's console never shows, and debugPrint
    // throttles — under the native logging this client emits, the lines that
    // mattered were the ones that went missing. Debug builds only.
    if (kDebugMode) stdout.writeln(line);
  }

  void _handleSignalingDone() {
    _logStatus('event stream closed', _connectionStatus);
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
