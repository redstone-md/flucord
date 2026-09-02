import 'dart:typed_data';

/// What is done to the microphone before it is encoded.
///
/// Off by default: the filter costs CPU on every frame, and a machine that
/// never asked for it should not pay.
final class VoiceProcessingSettings {
  const VoiceProcessingSettings({this.noiseSuppression = false});

  final bool noiseSuppression;

  VoiceProcessingSettings copyWith({bool? noiseSuppression}) =>
      VoiceProcessingSettings(
        noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      );

  Map<String, Object?> toJson() => {'noise_suppression': noiseSuppression};

  /// Reads stored settings, falling back per field: a file edited by hand
  /// must not stop the client.
  static VoiceProcessingSettings fromJson(Object? value) {
    if (value is! Map) return const VoiceProcessingSettings();
    final held = value['noise_suppression'];
    return VoiceProcessingSettings(noiseSuppression: held is bool && held);
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceProcessingSettings &&
      other.noiseSuppression == noiseSuppression;

  @override
  int get hashCode => noiseSuppression.hashCode;
}

/// Where the processing switches are kept between runs.
///
/// Local rather than on the account, like the stream quality: the filter runs
/// on this machine's CPU against this machine's microphone.
abstract interface class VoiceProcessingRepository {
  Future<VoiceProcessingSettings> load();
  Future<void> save(VoiceProcessingSettings settings);
}

/// Removes noise from the microphone, one frame at a time.
abstract interface class VoiceNoiseSuppressor {
  /// Samples per channel the model consumes at once. A frame handed to
  /// [process] holds a whole number of hops per channel.
  int get hopSize;

  /// Cleans one frame of interleaved 48 kHz PCM16, [channels] wide, in place.
  void process(Int16List frame, {required int channels});

  void dispose();
}
