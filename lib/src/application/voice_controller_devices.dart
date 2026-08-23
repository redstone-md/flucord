part of 'voice_controller.dart';

/// The device half of the controller: which microphone and speaker the session
/// uses, and whether the microphone is live.
///
/// Split out because none of it touches the connection state machine — it acts
/// on the media service and republishes — and keeping it beside the join and
/// leave paths made the file harder to follow than the two concerns are apart.
extension VoiceControllerDevices on VoiceController {
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
      await _applyMuteState();
      await _sendJoin();
    });
  }

  /// Silences, or unsilences, every path a voice can leave by.
  ///
  /// Each step is isolated. A single `await` chain here meant one failing
  /// call — a speaking frame that could not go out on a socket Discord had
  /// just closed — skipped the steps after it, and the one that actually stops
  /// the uplink was last: the button showed muted and the room still heard
  /// everything. Muting must not depend on anything succeeding.
  Future<void> _applyMuteState() async {
    final wantsUplink = !_isMuted && isTransportReady;
    // The pipeline first when going quiet: it is the one that puts packets on
    // the wire, so it is the one whose failure would be heard.
    if (!wantsUplink) {
      await _silence(() async => _audioPipeline?.setEnabled(false));
    }
    await _silence(() => _mediaService.setMicrophoneEnabled(!_isMuted));
    if (wantsUplink) {
      await _silence(() async => _audioPipeline?.setEnabled(true));
    }
  }

  Future<void> _silence(Future<void> Function() step) async {
    try {
      await step();
    } on Object catch (error) {
      // Reported, not rethrown: the remaining steps still have to run.
      _error = error;
    }
  }

  /// Silences the uplink for as long as the key is held.
  ///
  /// Separate from [toggleMute] because push to talk is not a toggle: two
  /// quick presses must not leave the microphone in the state the first one
  /// put it in.
  Future<void> setMuted({required bool muted}) async {
    if (!isConnected || _isMuted == muted) return;
    await _run(() async {
      _isMuted = muted;
      await _applyMuteState();
      await _sendJoin();
    });
  }

  /// Deafening also mutes, which is what Discord does: somebody who cannot
  /// hear the room should not still be speaking into it.
  Future<void> toggleDeafen() async {
    if (!isConnected) return;
    await _run(() async {
      _isDeafened = !_isDeafened;
      if (_isDeafened) _isMuted = true;
      await _applyMuteState();
      await _silence(
        () => _setPlaybackEnabled(!_isDeafened && isTransportReady),
      );
      await _sendJoin();
    });
  }
}
