part of 'voice_controller.dart';

/// The listening half of the controller: how loud each participant is, and
/// what happens to other applications while this account speaks.
///
/// Split out for the same reason the device half is: none of it touches the
/// connection state machine, and each edit here would otherwise have to be
/// read past pages of join and leave to be sure it changed none of it.
extension VoiceControllerListening on VoiceController {
  /// How loud one participant plays, as a fraction of the room's level.
  ///
  /// Read from the saved preferences, not from the playback service: a
  /// participant who has not spoken since the level was chosen has no source
  /// to ask.
  double volumeFor(String participant) =>
      _processing.listening.volumeFor(participant);

  /// Whether this machine can attenuate other applications at all.
  bool get isApplicationAttenuationAvailable =>
      _applicationAttenuation?.isSupported ?? false;

  /// Whether other applications are turned down while this account speaks.
  bool get attenuateApplications => _processing.listening.attenuateApplications;

  /// How far they are turned down: 0 not at all, 1 to silence.
  double get attenuationLevel => _processing.listening.attenuationLevel;

  /// Sets one participant's volume, for this session and the next.
  ///
  /// The level is remembered even before the participant's first frame, so
  /// a voice that starts a moment later opens at the chosen volume rather
  /// than one word at full level. This account's own tile is not offered a
  /// slider, but a value set by hand for it would change only what this
  /// client plays of itself, which is nothing: the level is still kept.
  Future<void> setParticipantVolume(String participant, double volume) async {
    final level = volume.clamp(0.0, 1.0);
    // A change the user made is a change the startup load must not undo.
    _processingTouched = true;
    _processing = _processing.copyWith(
      listening: _processing.listening.withParticipantVolume(
        participant,
        level,
      ),
    );
    final playbackService = _playbackService;
    if (playbackService != null) {
      try {
        await playbackService.setSourceVolume(participant, level);
      } on Object catch (error) {
        _reportBackgroundError(error);
      }
    }
    _notify();
    await _saveProcessing();
  }

  /// Switches attenuation of other applications, for this session and the
  /// next.
  Future<void> setAttenuateApplications(bool enabled) async {
    if (_processing.listening.attenuateApplications == enabled) return;
    // A change the user made is a change the startup load must not undo.
    _processingTouched = true;
    _processing = _processing.copyWith(
      listening: _processing.listening.copyWith(attenuateApplications: enabled),
    );
    if (!enabled) await _releaseAttenuation();
    _notify();
    await _saveProcessing();
  }

  /// Sets how far other applications are turned down while this account
  /// speaks, for this session and the next. Level 0 attenuation is the same
  /// as the switch being off.
  Future<void> setAttenuationLevel(double level) async {
    final held = level.clamp(0.0, 1.0);
    if (_processing.listening.attenuationLevel == held) return;
    // A change the user made is a change the startup load must not undo.
    _processingTouched = true;
    _processing = _processing.copyWith(
      listening: _processing.listening.copyWith(attenuationLevel: held),
    );
    // A burst already in progress keeps its old level until the next one;
    // changing the level mid-word would leave sessions held at a mix of
    // both. The next burst re-applies from the saved preferences.
    _notify();
    await _saveProcessing();
  }

  /// Attenuation follows this account's speech: down while the gate hears
  /// it, back up when the gate closes.
  ///
  /// Reported rather than thrown: a machine that cannot be reached here is
  /// the wrong volume, not a broken room.
  void _handleOwnSpeakingForAttenuation(bool speaking) {
    if (_disposed) return;
    final listening = _processing.listening;
    if (!listening.attenuateApplications) return;
    final attenuation = _applicationAttenuation;
    if (attenuation == null) return;
    if (speaking) {
      final level = listening.attenuationLevel;
      if (level <= 0) return;
      unawaited(
        attenuation.attenuate(level).catchError((Object error) {
          _reportBackgroundError(error);
        }),
      );
    } else {
      unawaited(
        attenuation.release().catchError((Object error) {
          _reportBackgroundError(error);
        }),
      );
    }
  }

  /// Releases the machine's other applications, used when the switch goes
  /// off and when the controller goes away.
  Future<void> _releaseAttenuation() async {
    final attenuation = _applicationAttenuation;
    if (attenuation == null) return;
    try {
      await attenuation.release();
    } on Object catch (error) {
      _reportBackgroundError(error);
    }
  }

  /// Saves the processing document, reporting a failure rather than hiding
  /// it: a file that will not write loses the next restart, not this
  /// session.
  Future<void> _saveProcessing() async {
    final repository = _processingRepository;
    if (repository == null) return;
    try {
      await repository.save(_processing);
    } on Object catch (error) {
      _reportBackgroundError(error);
    }
  }

  /// Applies every remembered participant level to the playback service.
  ///
  /// Called when the saved preferences arrive, which is once at startup and
  /// once more never: a level changed after that reaches the service from
  /// its own setter.
  Future<void> _applyParticipantVolumes() async {
    final playbackService = _playbackService;
    if (playbackService == null) return;
    for (final entry in _processing.listening.participantVolumes.entries) {
      try {
        await playbackService.setSourceVolume(entry.key, entry.value);
      } on Object catch (error) {
        _reportBackgroundError(error);
        return;
      }
    }
  }
}
