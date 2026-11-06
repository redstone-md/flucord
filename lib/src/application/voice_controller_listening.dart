part of 'voice_controller.dart';

/// The listening half of the controller: how loud each participant is, who
/// is muted for this client, and what happens to other applications while
/// this account speaks.
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
  /// than one word at full level. This account's own entry is not offered a
  /// volume, but a value set by hand for it would change only what this
  /// client plays of itself, which is nothing: the level is still kept.
  ///
  /// A participant muted for this client stays silent: the new level is
  /// saved and is what unmuting brings back.
  Future<void> setParticipantVolume(String participant, double volume) =>
      _changeParticipant(
        participant,
        _processing.listening.withParticipantVolume(participant, volume),
      );

  /// Whether [participant] is muted for this client only. Not this
  /// account's own microphone, which is [VoiceController.isMuted].
  bool isParticipantMuted(String participant) =>
      _processing.listening.mutedParticipants.contains(participant);

  /// Mutes or unmutes one participant for this client, for this session and
  /// the next. Their level is kept.
  Future<void> setParticipantMuted(String participant, bool muted) =>
      _changeParticipant(
        participant,
        _processing.listening.withParticipantMuted(participant, muted),
      );

  /// Whether this client skips the soundboard sounds [participant] plays.
  bool isSoundboardMuted(String participant) =>
      _processing.listening.soundboardMutedParticipants.contains(participant);

  /// Mutes or unmutes one participant's soundboard sounds, for this session
  /// and the next. Their voice is not touched.
  Future<void> setSoundboardMuted(String participant, bool muted) async {
    // A change the user made is a change the startup load must not undo.
    _processingTouched = true;
    _processing = _processing.copyWith(
      listening: _processing.listening.withSoundboardMuted(participant, muted),
    );
    _notify();
    await _saveProcessing();
  }

  /// Takes on [listening] as the user's choice for [participant], sets their
  /// source to the level it now plays at, and saves.
  Future<void> _changeParticipant(
    String participant,
    VoiceListeningSettings listening,
  ) async {
    // A change the user made is a change the startup load must not undo.
    _processingTouched = true;
    _processing = _processing.copyWith(listening: listening);
    final playbackService = _playbackService;
    if (playbackService != null) {
      try {
        await playbackService.setSourceVolume(
          participant,
          listening.playedVolumeFor(participant),
        );
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

  /// Applies every remembered participant level and mute to the playback
  /// service.
  ///
  /// Called when the saved preferences arrive, which is once at startup and
  /// once more never: a level changed after that reaches the service from
  /// its own setter. A muted participant at full level has no volume entry,
  /// so the mutes are walked as well.
  Future<void> _applyParticipantVolumes() async {
    final playbackService = _playbackService;
    if (playbackService == null) return;
    final listening = _processing.listening;
    final participants = {
      ...listening.participantVolumes.keys,
      ...listening.mutedParticipants,
    };
    try {
      await Future.wait([
        for (final participant in participants)
          playbackService.setSourceVolume(
            participant,
            listening.playedVolumeFor(participant),
          ),
      ]);
    } on Object catch (error) {
      _reportBackgroundError(error);
    }
  }
}
