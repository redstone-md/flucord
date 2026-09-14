import 'dart:typed_data';

/// What is done to the microphone before it is encoded, and how the room's
/// sound is listened to.
///
/// Both halves belong to the machine rather than the account: the filter
/// runs on this machine's CPU against this machine's microphone, and the
/// listening preferences describe who is sitting at it.
final class VoiceProcessingSettings {
  const VoiceProcessingSettings({
    this.noiseSuppression = false,
    this.listening = const VoiceListeningSettings(),
    this.inputSensitivity,
    this.pushToTalkReleaseDelayMs = 0,
    this.echoCancellation = true,
    this.automaticGainControl = true,
  });

  /// Off by default: the filter costs CPU on every frame, and a machine that
  /// never asked for it should not pay.
  final bool noiseSuppression;

  /// The level the microphone has to reach to count as speech, in dB relative
  /// to full scale. Null means the gate learns the room's noise floor and
  /// sits a margin above it: a threshold chosen by hand describes a specific
  /// microphone in a specific room better than any floor can.
  final double? inputSensitivity;

  /// How long the uplink stays live after the push-to-talk key is released,
  /// in milliseconds. Zero ends speech with the key, which is what a toggle
  /// user experiences.
  final int pushToTalkReleaseDelayMs;

  /// Removes what the speakers are playing from the microphone, so the room
  /// does not hear itself. On by default, as Discord has it.
  final bool echoCancellation;

  /// Keeps the microphone's level steady without anybody touching a knob.
  /// On by default, as Discord has it.
  final bool automaticGainControl;

  final VoiceListeningSettings listening;

  VoiceProcessingSettings copyWith({
    bool? noiseSuppression,
    VoiceListeningSettings? listening,
    double? inputSensitivity,
    bool? automaticSensitivity,
    int? pushToTalkReleaseDelayMs,
    bool? echoCancellation,
    bool? automaticGainControl,
  }) => VoiceProcessingSettings(
    noiseSuppression: noiseSuppression ?? this.noiseSuppression,
    listening: listening ?? this.listening,
    // Null is a value here: it is the automatic gate, which a copyWith that
    // could not pass it through would never be able to switch back to.
    inputSensitivity: automaticSensitivity == true
        ? null
        : inputSensitivity ?? this.inputSensitivity,
    pushToTalkReleaseDelayMs:
        pushToTalkReleaseDelayMs ?? this.pushToTalkReleaseDelayMs,
    echoCancellation: echoCancellation ?? this.echoCancellation,
    automaticGainControl: automaticGainControl ?? this.automaticGainControl,
  );

  Map<String, Object?> toJson() => {
    'noise_suppression': noiseSuppression,
    'listening': listening.toJson(),
    // Absent when automatic: the switch back must read as a fresh machine.
    'input_sensitivity': ?inputSensitivity,
    'push_to_talk_release_delay_ms': pushToTalkReleaseDelayMs,
    'echo_cancellation': echoCancellation,
    'automatic_gain_control': automaticGainControl,
  };

  /// Reads stored settings, falling back per field: a file edited by hand
  /// must not stop the client.
  static VoiceProcessingSettings fromJson(Object? value) {
    if (value is! Map) return const VoiceProcessingSettings();
    final held = value['noise_suppression'];
    final sensitivity = value['input_sensitivity'];
    final releaseDelay = value['push_to_talk_release_delay_ms'];
    final echoCancellation = value['echo_cancellation'];
    final gainControl = value['automatic_gain_control'];
    return VoiceProcessingSettings(
      noiseSuppression: held is bool && held,
      listening: VoiceListeningSettings.fromJson(value['listening']),
      inputSensitivity: sensitivity is num ? sensitivity.toDouble() : null,
      pushToTalkReleaseDelayMs: releaseDelay is int && releaseDelay >= 0
          ? releaseDelay
          : 0,
      echoCancellation: echoCancellation is bool ? echoCancellation : true,
      automaticGainControl: gainControl is bool ? gainControl : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceProcessingSettings &&
      other.noiseSuppression == noiseSuppression &&
      other.listening == listening &&
      other.inputSensitivity == inputSensitivity &&
      other.pushToTalkReleaseDelayMs == pushToTalkReleaseDelayMs &&
      other.echoCancellation == echoCancellation &&
      other.automaticGainControl == automaticGainControl;

  @override
  int get hashCode => Object.hash(
    noiseSuppression,
    listening,
    inputSensitivity,
    pushToTalkReleaseDelayMs,
    echoCancellation,
    automaticGainControl,
  );
}

/// The room-listening preferences: how loud each participant is, and what
/// happens to other applications while this account speaks.
///
/// Per-participant volume is keyed by participant: the level travels with the
/// person, so a room joined tomorrow starts where today's left off. A
/// participant with no entry plays at the room's level.
final class VoiceListeningSettings {
  const VoiceListeningSettings({
    this.participantVolumes = const {},
    this.attenuateApplications = false,
    this.attenuationLevel = defaultAttenuationLevel,
  });

  /// How far other applications are turned down while this account speaks,
  /// as a fraction of their own volume. Discord's own default.
  static const double defaultAttenuationLevel = 0.8;

  final Map<String, double> participantVolumes;

  /// Whether other applications are turned down while this account speaks.
  final bool attenuateApplications;

  /// How far they are turned down: 0 not at all, 1 to silence.
  final double attenuationLevel;

  /// The level [participant] plays at, or the room's level when none was
  /// chosen for them.
  double volumeFor(String participant) {
    final held = participantVolumes[participant];
    if (held == null) return 1;
    return held.clamp(0.0, 1.0);
  }

  VoiceListeningSettings copyWith({
    Map<String, double>? participantVolumes,
    bool? attenuateApplications,
    double? attenuationLevel,
  }) => VoiceListeningSettings(
    participantVolumes: participantVolumes ?? this.participantVolumes,
    attenuateApplications: attenuateApplications ?? this.attenuateApplications,
    attenuationLevel: attenuationLevel ?? this.attenuationLevel,
  );

  /// The same preferences with [participant] at [volume] instead.
  ///
  /// Full level is not stored: a participant nobody has turned up or down
  /// has no entry, the same as one whose level was set and then set back.
  VoiceListeningSettings withParticipantVolume(
    String participant,
    double volume,
  ) {
    final level = volume.clamp(0.0, 1.0);
    final volumes = {...participantVolumes};
    if (level == 1) {
      volumes.remove(participant);
    } else {
      volumes[participant] = level;
    }
    return copyWith(participantVolumes: volumes);
  }

  Map<String, Object?> toJson() => {
    'participant_volumes': {
      for (final entry in participantVolumes.entries)
        if (entry.value != 1) entry.key: entry.value,
    },
    'attenuate_applications': attenuateApplications,
    'attenuation_level': attenuationLevel,
  };

  /// Reads stored preferences, falling back per field: a hand-edited file
  /// must not stop the client, and a volume that is not a number keeps the
  /// room's level.
  static VoiceListeningSettings fromJson(Object? value) {
    if (value is! Map) return const VoiceListeningSettings();
    final volumes = value['participant_volumes'];
    final heldVolumes = <String, double>{};
    if (volumes is Map) {
      for (final entry in volumes.entries) {
        if (entry.value is num) {
          heldVolumes[entry.key.toString()] = (entry.value as num).toDouble();
        }
      }
    }
    final attenuate = value['attenuate_applications'];
    final level = value['attenuation_level'];
    return VoiceListeningSettings(
      participantVolumes: heldVolumes,
      attenuateApplications: attenuate is bool && attenuate,
      attenuationLevel: level is num
          ? level.toDouble().clamp(0.0, 1.0)
          : defaultAttenuationLevel,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceListeningSettings &&
      other.attenuateApplications == attenuateApplications &&
      other.attenuationLevel == attenuationLevel &&
      _sameVolumes(other.participantVolumes);

  bool _sameVolumes(Map<String, double> other) {
    if (other.length != participantVolumes.length) return false;
    for (final entry in participantVolumes.entries) {
      if (other[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    attenuateApplications,
    attenuationLevel,
    participantVolumes.length,
  );
}

/// Where the processing switches and listening preferences are kept between
/// runs.
///
/// Local rather than on the account, like the stream quality: the filter runs
/// on this machine's CPU against this machine's microphone, and who is too
/// loud is a fact about this account's ears at this machine.
abstract interface class VoiceProcessingRepository {
  Future<VoiceProcessingSettings> load();
  Future<void> save(VoiceProcessingSettings settings);
}

/// Turns other applications down while this account speaks, and back up
/// when the account stops.
///
/// A machine-level effect, not a voice-connection one: Discord attenuates
/// whatever is playing whenever the microphone is live and carries speech,
/// so the contract speaks only of a level and of releasing it.
abstract interface class ApplicationAttenuation {
  bool get isSupported;

  /// Turns other applications down by [level] (0 to 1: the fraction of
  /// their own volume taken away). Level 0 is the same as releasing.
  Future<void> attenuate(double level);

  /// Puts every other application back where it was.
  Future<void> release();

  Future<void> dispose();
}

/// Removes noise from the microphone, one frame at a time.
abstract interface class VoiceNoiseSuppressor {
  /// Samples per channel the model consumes at once. A frame handed to
  /// [process] holds a whole number of hops per channel.
  int get hopSize;

  /// Cleans one frame of interleaved 48 kHz PCM16, [channels] wide, in place.
  ///
  /// Answers a future because the work may run where the model lives rather
  /// than on the caller's isolate; the caller chains its frames, so order is
  /// kept whichever side does the cleaning.
  Future<void> process(Int16List frame, {required int channels});

  void dispose();
}

/// Enhances the microphone, one frame at a time: removes what the machine's
/// speakers are playing from it and keeps its level steady.
///
/// Sits where the noise filter sits, between the framer and the encoder,
/// and sees the frame before the filter does: echo removal wants the raw
/// microphone, with the room's own voices still in it, or there is nothing
/// for the speaker line to match against. The machine's own audio layer
/// supplies the speaker line: what is actually playing, and when, is a fact
/// only it can know.
abstract interface class VoiceMicrophoneEnhancer {
  /// Enhances one frame of interleaved 48 kHz PCM16, [channels] wide, in
  /// place.
  ///
  /// Answers a future because the work may run where the enhancement lives
  /// rather than on the caller's isolate; the caller chains its frames, so
  /// order is kept whichever side does the work.
  Future<void> process(Int16List frame, {required int channels});

  void dispose();
}
