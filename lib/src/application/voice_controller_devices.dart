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
  ///
  /// A release with a release delay configured does not end the speech at
  /// once: the uplink stays live for the delay, so the ends of words survive
  /// the key. A press inside the window cancels the pending end, and the
  /// uplink that never dropped needs no restart. A toggle mute or a deafen
  /// takes effect immediately regardless: they are deliberate acts with no
  /// key to outrun.
  Future<void> setMuted({required bool muted}) async {
    if (!isConnected) return;
    // A press inside the release window cancels the pending end, whatever
    // the flag already reads: the uplink never dropped, but the timer that
    // would drop it is still running.
    if (muted == false) {
      _releaseDelayTimer?.cancel();
      _releaseDelayTimer = null;
    }
    if (_isMuted == muted) return;
    if (muted && !_isDeafened && _processing.pushToTalkReleaseDelayMs > 0) {
      // The key came up: keep transmitting for the configured window. The
      // room is not told anything, because nothing changed for it.
      _releaseDelayTimer = Timer(
        Duration(milliseconds: _processing.pushToTalkReleaseDelayMs),
        () {
          _releaseDelayTimer = null;
          unawaited(_endReleaseDelay());
        },
      );
      return;
    }
    await _run(() async {
      _isMuted = muted;
      await _applyMuteState();
      await _sendJoin();
    });
  }

  /// The release delay ran out: the uplink goes quiet now, unless the
  /// session changed underneath it. The timer's own existence is what held
  /// the uplink live, so nothing else needs to be checked against it.
  Future<void> _endReleaseDelay() async {
    if (!isConnected) return;
    await _run(() async {
      _isMuted = true;
      await _applyMuteState();
      await _sendJoin();
    });
  }

  /// Whether this build can clean the microphone at all.
  bool get isNoiseSuppressionAvailable =>
      _audioPipeline?.isNoiseSuppressionAvailable ?? false;

  /// Whether the microphone is being cleaned.
  ///
  /// Read from the pipeline, which turns itself off when the filter fails,
  /// so the switch shows what is happening rather than what was saved.
  bool get noiseSuppression =>
      _audioPipeline?.isNoiseSuppressionEnabled ?? _processing.noiseSuppression;

  /// Reads the processing switches from the machine's file and applies them,
  /// unless the user has already chosen since.
  Future<void> loadProcessingSettings() async {
    final repository = _processingRepository;
    if (repository == null) return;
    final loaded = await repository.load();
    if (_processingTouched || _disposed) return;
    _processing = loaded;
    unawaited(_audioPipeline?.setNoiseSuppression(loaded.noiseSuppression));
    _audioPipeline?.setInputThreshold(loaded.inputSensitivity);
    unawaited(
      _audioPipeline?.setMicrophoneEnhancement(
        echoCancellation: loaded.echoCancellation,
        automaticGainControl: loaded.automaticGainControl,
      ),
    );
    unawaited(_applyParticipantVolumes());
    _notify();
  }

  /// Switches the microphone filter, for this session and the next.
  ///
  /// Applied before it is saved: a file that will not write loses the next
  /// restart, not this call, and the failure is reported rather than hidden.
  /// The filter itself opens in the background; the pipeline reports if it
  /// cannot, and [noiseSuppression] falls back to off with it.
  Future<void> setNoiseSuppression(bool enabled) async {
    _processingTouched = true;
    if (_processing.noiseSuppression == enabled) return;
    _processing = _processing.copyWith(noiseSuppression: enabled);
    unawaited(_audioPipeline?.setNoiseSuppression(enabled));
    _notify();
    try {
      await _processingRepository?.save(_processing);
    } on Object catch (error) {
      _reportBackgroundError(error);
    }
  }

  /// The level the microphone has to reach to be sent, in dB relative to
  /// full scale, or null when the gate learns the room's noise floor.
  double? get inputSensitivity =>
      _audioPipeline?.inputSensitivity ?? _processing.inputSensitivity;

  /// Sets the gate's level by hand, for this session and the next, or
  /// returns to the automatic gate with null.
  Future<void> setInputSensitivity(double? dbfs) async {
    _processingTouched = true;
    // Null is a value here: it is the automatic gate, which a copyWith that
    // took it for "unchanged" would never be able to switch back to.
    _processing = _processing.copyWith(
      inputSensitivity: dbfs,
      automaticSensitivity: dbfs == null,
    );
    _audioPipeline?.setInputThreshold(dbfs);
    _notify();
    await _saveProcessing();
  }

  /// How long the uplink stays live after the push-to-talk key is released.
  int get pushToTalkReleaseDelayMs => _processing.pushToTalkReleaseDelayMs;

  /// Sets the release delay, for this session and the next.
  Future<void> setPushToTalkReleaseDelayMs(int ms) async {
    final held = ms < 0 ? 0 : ms;
    _processingTouched = true;
    _processing = _processing.copyWith(pushToTalkReleaseDelayMs: held);
    _notify();
    await _saveProcessing();
  }

  /// Whether this build has the machine's echo and gain stages at all.
  bool get isMicrophoneEnhancementAvailable =>
      _audioPipeline?.isMicrophoneEnhancementAvailable ?? false;

  /// Whether the microphone's echo is being removed.
  ///
  /// Read from the pipeline, which turns itself off when the stages fail,
  /// so the switch shows what is happening rather than what was asked for.
  bool get echoCancellation =>
      _audioPipeline?.isEchoCancellationEnabled ?? _processing.echoCancellation;

  /// Whether the microphone's level is being kept steady.
  bool get automaticGainControl =>
      _audioPipeline?.isAutomaticGainControlEnabled ??
      _processing.automaticGainControl;

  /// Switches the machine's echo and gain stages, for this session and the
  /// next.
  ///
  /// Applied before it is saved, like the noise filter: a file that will
  /// not write loses the next restart, not this call. Both switches ride
  /// one open path, and the pipeline reports if it cannot be opened.
  Future<void> setMicrophoneEnhancement({
    bool? echoCancellation,
    bool? automaticGainControl,
  }) async {
    _processingTouched = true;
    final next = _processing.copyWith(
      echoCancellation: echoCancellation,
      automaticGainControl: automaticGainControl,
    );
    if (next.echoCancellation == _processing.echoCancellation &&
        next.automaticGainControl == _processing.automaticGainControl) {
      return;
    }
    _processing = next;
    unawaited(
      _audioPipeline?.setMicrophoneEnhancement(
        echoCancellation: next.echoCancellation,
        automaticGainControl: next.automaticGainControl,
      ),
    );
    _notify();
    await _saveProcessing();
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
