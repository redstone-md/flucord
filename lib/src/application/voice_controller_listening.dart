part of 'voice_controller.dart';

/// The listening half of the controller: how loud each participant and each
/// Stream is, who is muted for this client, and what happens to other
/// applications while this account speaks.
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
  Future<void> setSoundboardMuted(String participant, bool muted) =>
      _changeListening(
        _processing.listening.withSoundboardMuted(participant, muted),
        const {},
      );

  /// How loud [sender]'s Stream plays, 0 to 1. Apart from their voice.
  double streamVolumeFor(String sender) =>
      _processing.listening.streamVolumeFor(sender);

  /// Whether [sender]'s Stream sound is muted for this client.
  bool isStreamMuted(String sender) =>
      _processing.listening.mutedStreams.contains(sender);

  /// Sets how loud [sender]'s Stream plays, for the sessions playing now and
  /// every later one. Clamped to 0 to 1; their voice is not touched.
  Future<void> setStreamVolume(String sender, double volume) => _changeStream(
    sender,
    _processing.listening.withStreamVolume(sender, volume),
  );

  /// Mutes or unmutes [sender]'s Stream sound. The picture plays on, and
  /// the level is kept for unmuting.
  Future<void> setStreamMuted(String sender, bool muted) => _changeStream(
    sender,
    _processing.listening.withStreamMuted(sender, muted),
  );

  Future<void> _changeParticipant(
    String participant,
    VoiceListeningSettings listening,
  ) => _changeListening(listening, {
    participant: listening.playedVolumeFor(participant),
  });

  Future<void> _changeStream(String sender, VoiceListeningSettings listening) {
    final level = listening.playedStreamVolumeFor(sender);
    return _changeListening(listening, {
      for (final source in _streamSources[sender] ?? const <String>{})
        source: level,
    });
  }

  /// Takes on [listening] as the user's choice, sets each of [levels]'
  /// sources to the level it now plays at, and saves.
  Future<void> _changeListening(
    VoiceListeningSettings listening,
    Map<String, double> levels,
  ) async {
    // A change the user made is a change the startup load must not undo.
    _processingTouched = true;
    _processing = _processing.copyWith(listening: listening);
    await _setSourceVolumes(levels);
    _notify();
    await _saveProcessing();
  }

  /// Notes the first frame of a watched session's source and starts it at
  /// its Sender's level. Called for every frame that is not a voice.
  ///
  /// The level is set before the frame reaches playback, so the session
  /// does not play a moment at full level. A Sender at full level needs no
  /// entry at all: a source plays at full level by default.
  void _openStreamSource(String sourceId) {
    final sender = GoLiveStreamKey.ofAudioSource(sourceId)?.userId;
    if (sender == null) return;
    if (!(_streamSources[sender] ??= {}).add(sourceId)) return;
    final level = _processing.listening.playedStreamVolumeFor(sender);
    if (level != 1) unawaited(_setSourceVolumes({sourceId: level}));
  }

  /// Forgets a watched session's source once its sound has ended.
  void _closeStreamSource(String sourceId) {
    final sender = GoLiveStreamKey.ofAudioSource(sourceId)?.userId;
    final sources = _streamSources[sender];
    if (sources == null) return;
    sources.remove(sourceId);
    if (sources.isEmpty) _streamSources.remove(sender);
  }

  /// Sets each source to its level in the playback service. A failure is
  /// reported, not thrown: it is the wrong volume, not a broken room.
  Future<void> _setSourceVolumes(Map<String, double> levels) async {
    final playbackService = _playbackService;
    if (playbackService == null || levels.isEmpty) return;
    try {
      await Future.wait([
        for (final MapEntry(key: source, value: level) in levels.entries)
          playbackService.setSourceVolume(source, level),
      ]);
    } on Object catch (error) {
      _reportBackgroundError(error);
    }
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

  /// Applies every remembered participant level and mute, and the Stream
  /// level of every watched session already playing, to the playback
  /// service.
  ///
  /// Called when the saved preferences arrive, which is once at startup and
  /// once more never: a level changed after that reaches the service from
  /// its own setter. A muted participant at full level has no volume entry,
  /// so the mutes are walked as well.
  Future<void> _applyListeningVolumes() {
    final listening = _processing.listening;
    final participants = {
      ...listening.participantVolumes.keys,
      ...listening.mutedParticipants,
    };
    return _setSourceVolumes({
      for (final participant in participants)
        participant: listening.playedVolumeFor(participant),
      for (final MapEntry(key: sender, value: sources)
          in _streamSources.entries)
        for (final source in sources)
          source: listening.playedStreamVolumeFor(sender),
    });
  }
}
