/// What a share and a camera are encoded at, in bits per second.
///
/// The defaults are Discord's web-client policy, not physics: the web client
/// is capped at 2500 kbps for a share and sends camera video smaller, and a
/// desktop client may use more. This object is the one home of those numbers;
/// everywhere else reads them from here.
final class StreamQualitySettings {
  const StreamQualitySettings({
    this.shareBitrate = defaultShareBitrate,
    this.cameraBitrate = defaultCameraBitrate,
  });

  /// Discord's own default for a 720p30 share.
  static const defaultShareBitrate = 2500000;

  /// What a webcam picture is sent at: it carries far less detail than a
  /// desktop full of text.
  static const defaultCameraBitrate = 1200000;

  final int shareBitrate;
  final int cameraBitrate;

  /// Whether both numbers can be handed to an encoder. A bitrate that is not
  /// a positive number is refused rather than clamped: the picker bounds the
  /// choice already, so anything else arrived by hand.
  bool get isValid => shareBitrate > 0 && cameraBitrate > 0;

  StreamQualitySettings copyWith({int? shareBitrate, int? cameraBitrate}) =>
      StreamQualitySettings(
        shareBitrate: shareBitrate ?? this.shareBitrate,
        cameraBitrate: cameraBitrate ?? this.cameraBitrate,
      );

  Map<String, Object?> toJson() => {
    'share_bitrate': shareBitrate,
    'camera_bitrate': cameraBitrate,
  };

  /// Reads stored settings, falling back per field.
  ///
  /// A file written by a newer build, or edited by hand, must not stop the
  /// client: an unreadable bitrate simply keeps its default.
  static StreamQualitySettings fromJson(Object? value) {
    if (value is! Map) return const StreamQualitySettings();
    int read(String key, int fallback) {
      final held = value[key];
      return held is int && held > 0 ? held : fallback;
    }

    return StreamQualitySettings(
      shareBitrate: read('share_bitrate', defaultShareBitrate),
      cameraBitrate: read('camera_bitrate', defaultCameraBitrate),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StreamQualitySettings &&
      other.shareBitrate == shareBitrate &&
      other.cameraBitrate == cameraBitrate;

  @override
  int get hashCode => Object.hash(shareBitrate, cameraBitrate);
}

/// Where the bitrates are kept between runs.
///
/// Local rather than on the account, for the same reason the streamer mode
/// switches are: they describe the machine's connection, and Discord's
/// settings blob has no group for them.
abstract interface class StreamQualityRepository {
  Future<StreamQualitySettings> load();
  Future<void> save(StreamQualitySettings settings);
}
