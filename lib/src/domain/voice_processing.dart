import 'dart:typed_data';

import 'package:collection/collection.dart';

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
    this.inputDevice,
    this.outputDevice,
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

  /// The microphone and the speakers chosen last, or null for the first the
  /// system lists. Kept on this machine, as Discord keeps them.
  final VoiceDeviceChoice? inputDevice;
  final VoiceDeviceChoice? outputDevice;

  VoiceProcessingSettings copyWith({
    bool? noiseSuppression,
    VoiceListeningSettings? listening,
    double? inputSensitivity,
    bool? automaticSensitivity,
    int? pushToTalkReleaseDelayMs,
    bool? echoCancellation,
    bool? automaticGainControl,
    VoiceDeviceChoice? inputDevice,
    VoiceDeviceChoice? outputDevice,
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
    inputDevice: inputDevice ?? this.inputDevice,
    outputDevice: outputDevice ?? this.outputDevice,
  );

  Map<String, Object?> toJson() => {
    'noise_suppression': noiseSuppression,
    'listening': listening.toJson(),
    // Absent when automatic: the switch back must read as a fresh machine.
    'input_sensitivity': ?inputSensitivity,
    'push_to_talk_release_delay_ms': pushToTalkReleaseDelayMs,
    'echo_cancellation': echoCancellation,
    'automatic_gain_control': automaticGainControl,
    'input_device': ?inputDevice?.toJson(),
    'output_device': ?outputDevice?.toJson(),
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
      inputDevice: VoiceDeviceChoice.fromJson(value['input_device']),
      outputDevice: VoiceDeviceChoice.fromJson(value['output_device']),
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
      other.automaticGainControl == automaticGainControl &&
      other.inputDevice == inputDevice &&
      other.outputDevice == outputDevice;

  @override
  int get hashCode => Object.hash(
    noiseSuppression,
    listening,
    inputSensitivity,
    pushToTalkReleaseDelayMs,
    echoCancellation,
    automaticGainControl,
    inputDevice,
    outputDevice,
  );
}

/// A microphone or speakers somebody chose: the system's id for it, and the
/// name it showed, which finds it again when the system gives it another id.
final class VoiceDeviceChoice {
  const VoiceDeviceChoice({required this.id, required this.label});

  final String id;
  final String label;

  /// Null for anything but an object with a non-empty id.
  static VoiceDeviceChoice? fromJson(Object? value) => switch (value) {
    {'id': final String id, 'label': final String label} when id.isNotEmpty =>
      VoiceDeviceChoice(id: id, label: label),
    _ => null,
  };

  Map<String, Object?> toJson() => {'id': id, 'label': label};

  @override
  bool operator ==(Object other) =>
      other is VoiceDeviceChoice && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// The room-listening preferences: how loud each participant and each
/// Stream is, who is muted for this client, and what happens to other
/// applications while this account speaks.
///
/// Per-participant choices are keyed by participant: they travel with the
/// person, so a room joined tomorrow starts where today's left off. A
/// participant with no entry plays at the room's level and is not muted.
/// Stream choices are keyed by Sender the same way, apart from their voice
/// (ADR-0012).
final class VoiceListeningSettings {
  const VoiceListeningSettings({
    this.participantVolumes = const {},
    this.mutedParticipants = const {},
    this.soundboardMutedParticipants = const {},
    this.streamVolumes = const {},
    this.mutedStreams = const {},
    this.attenuateApplications = false,
    this.attenuationLevel = defaultAttenuationLevel,
  });

  /// How far other applications are turned down while this account speaks,
  /// as a fraction of their own volume. Discord's own default.
  static const double defaultAttenuationLevel = 0.8;

  /// The loudest a participant can be turned up: twice the room's level.
  static const double maxParticipantVolume = 2;

  final Map<String, double> participantVolumes;

  /// Participants silenced for this client only. Their level is kept, so
  /// unmuting brings back the level chosen before.
  final Set<String> mutedParticipants;

  /// Participants whose soundboard sounds this client does not play. Their
  /// voice is not touched.
  final Set<String> soundboardMutedParticipants;

  /// How loud each Sender's Stream plays, 0 to 1, by Sender. A Sender with
  /// no entry plays at full level.
  final Map<String, double> streamVolumes;

  /// Senders whose Stream sound is silenced for this client. Their level is
  /// kept, and their voice is not touched.
  final Set<String> mutedStreams;

  /// Whether other applications are turned down while this account speaks.
  final bool attenuateApplications;

  /// How far they are turned down: 0 not at all, 1 to silence.
  final double attenuationLevel;

  /// The level [participant] plays at, or the room's level when none was
  /// chosen for them. A mute does not change it.
  double volumeFor(String participant) {
    final held = participantVolumes[participant];
    if (held == null) return 1;
    return held.clamp(0.0, maxParticipantVolume);
  }

  /// The level the playback source of [participant] is set to: silent while
  /// they are muted, their chosen level otherwise.
  double playedVolumeFor(String participant) =>
      mutedParticipants.contains(participant) ? 0 : volumeFor(participant);

  /// The level [sender]'s Stream plays at, or full level when none was
  /// chosen. A mute does not change it.
  double streamVolumeFor(String sender) =>
      (streamVolumes[sender] ?? 1).clamp(0.0, 1.0);

  /// The level a playback source of [sender]'s Stream is set to: silent
  /// while the Stream is muted, its chosen level otherwise.
  double playedStreamVolumeFor(String sender) =>
      mutedStreams.contains(sender) ? 0 : streamVolumeFor(sender);

  VoiceListeningSettings copyWith({
    Map<String, double>? participantVolumes,
    Set<String>? mutedParticipants,
    Set<String>? soundboardMutedParticipants,
    Map<String, double>? streamVolumes,
    Set<String>? mutedStreams,
    bool? attenuateApplications,
    double? attenuationLevel,
  }) => VoiceListeningSettings(
    participantVolumes: participantVolumes ?? this.participantVolumes,
    mutedParticipants: mutedParticipants ?? this.mutedParticipants,
    soundboardMutedParticipants:
        soundboardMutedParticipants ?? this.soundboardMutedParticipants,
    streamVolumes: streamVolumes ?? this.streamVolumes,
    mutedStreams: mutedStreams ?? this.mutedStreams,
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
    return copyWith(
      participantVolumes: _withLevel(
        participantVolumes,
        participant,
        volume.clamp(0.0, maxParticipantVolume),
      ),
    );
  }

  /// The same preferences with [sender]'s Stream at [volume], 0 to 1. Full
  /// level is not stored, as for participants.
  VoiceListeningSettings withStreamVolume(String sender, double volume) =>
      copyWith(
        streamVolumes: _withLevel(
          streamVolumes,
          sender,
          volume.clamp(0.0, 1.0),
        ),
      );

  /// The same preferences with [sender]'s Stream muted or unmuted.
  VoiceListeningSettings withStreamMuted(String sender, bool muted) =>
      copyWith(mutedStreams: _toggled(mutedStreams, sender, muted));

  static Map<String, double> _withLevel(
    Map<String, double> levels,
    String id,
    double level,
  ) => level == 1 ? ({...levels}..remove(id)) : {...levels, id: level};

  /// The same preferences with [participant] muted or unmuted for this
  /// client.
  VoiceListeningSettings withParticipantMuted(String participant, bool muted) =>
      copyWith(
        mutedParticipants: _toggled(mutedParticipants, participant, muted),
      );

  /// The same preferences with [participant]'s soundboard muted or not.
  VoiceListeningSettings withSoundboardMuted(String participant, bool muted) =>
      copyWith(
        soundboardMutedParticipants: _toggled(
          soundboardMutedParticipants,
          participant,
          muted,
        ),
      );

  static Set<String> _toggled(Set<String> ids, String id, bool present) =>
      present ? {...ids, id} : ({...ids}..remove(id));

  Map<String, Object?> toJson() => {
    'participant_volumes': _storedLevels(participantVolumes),
    'muted_participants': mutedParticipants.toList(),
    'soundboard_muted_participants': soundboardMutedParticipants.toList(),
    'stream_volumes': _storedLevels(streamVolumes),
    'muted_streams': mutedStreams.toList(),
    'attenuate_applications': attenuateApplications,
    'attenuation_level': attenuationLevel,
  };

  /// Full level is the default and is not written.
  static Map<String, double> _storedLevels(Map<String, double> levels) => {
    for (final MapEntry(:key, :value) in levels.entries)
      if (value != 1) key: value,
  };

  /// Reads stored preferences, falling back per field: a hand-edited file
  /// must not stop the client, and a volume that is not a number keeps the
  /// room's level. A file written before mutes existed reads as nobody
  /// muted.
  static VoiceListeningSettings fromJson(Object? value) {
    if (value is! Map) return const VoiceListeningSettings();
    final attenuate = value['attenuate_applications'];
    final level = value['attenuation_level'];
    return VoiceListeningSettings(
      participantVolumes: _levelsFrom(value['participant_volumes']),
      mutedParticipants: _idsFrom(value['muted_participants']),
      soundboardMutedParticipants: _idsFrom(
        value['soundboard_muted_participants'],
      ),
      streamVolumes: _levelsFrom(value['stream_volumes']),
      mutedStreams: _idsFrom(value['muted_streams']),
      attenuateApplications: attenuate is bool && attenuate,
      attenuationLevel: level is num
          ? level.toDouble().clamp(0.0, 1.0)
          : defaultAttenuationLevel,
    );
  }

  /// The levels in a stored map; an entry that is not a number is dropped,
  /// so it plays at full level.
  static Map<String, double> _levelsFrom(Object? value) => {
    if (value is Map)
      for (final MapEntry(:key, value: level) in value.entries)
        if (level is num) key.toString(): level.toDouble(),
  };

  /// The participant ids in a stored list; anything that is not a string is
  /// dropped.
  static Set<String> _idsFrom(Object? value) =>
      value is List ? value.whereType<String>().toSet() : const {};

  static const _volumesEquality = MapEquality<String, double>();
  static const _idsEquality = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is VoiceListeningSettings &&
      other.attenuateApplications == attenuateApplications &&
      other.attenuationLevel == attenuationLevel &&
      _volumesEquality.equals(other.participantVolumes, participantVolumes) &&
      _idsEquality.equals(other.mutedParticipants, mutedParticipants) &&
      _idsEquality.equals(
        other.soundboardMutedParticipants,
        soundboardMutedParticipants,
      ) &&
      _volumesEquality.equals(other.streamVolumes, streamVolumes) &&
      _idsEquality.equals(other.mutedStreams, mutedStreams);

  @override
  int get hashCode => Object.hash(
    attenuateApplications,
    attenuationLevel,
    _volumesEquality.hash(participantVolumes),
    _idsEquality.hash(mutedParticipants),
    _idsEquality.hash(soundboardMutedParticipants),
    _volumesEquality.hash(streamVolumes),
    _idsEquality.hash(mutedStreams),
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
/// The two stages sit on either side of the noise filter, between the
/// framer and the encoder, in the order WebRTC's own pipeline runs them.
/// Echo removal comes first: it wants the raw microphone, with the room's
/// own voices still in it, or there is nothing for the speaker line to
/// match against. Gain comes last: a level judged on a noisy microphone
/// lifts the noise along with the voice, and hands the filter more to
/// remove. The machine's own audio layer supplies the speaker line: what
/// is actually playing, and when, is a fact only it can know.
///
/// Each step works on one frame of interleaved 48 kHz PCM16, [channels]
/// wide, in place, and does nothing when its stage is off. It answers a
/// future because the work may run where the enhancement lives rather than
/// on the caller's isolate; the caller chains its frames, so order is kept
/// whichever side does the work.
abstract interface class VoiceMicrophoneEnhancer {
  /// Takes what the speakers play out of [frame].
  Future<void> cancelEcho(Int16List frame, {required int channels});

  /// Keeps [frame]'s level steady.
  Future<void> controlGain(Int16List frame, {required int channels});

  /// Takes the speaker line from the output named [speakers], as the
  /// playback's device list names it, or from the system default when null:
  /// the echo to remove is whatever the room is played on.
  void loopBack(String? speakers);

  void dispose();
}
