/// The sizes a share can be sent at, the ones Discord's own picker offers.
/// Sixteen by nine, which is what the capture is scaled to whatever the
/// desktop's shape.
enum StreamResolution {
  p480(854, 480),
  p720(1280, 720),
  p1080(1920, 1080),
  p1440(2560, 1440);

  const StreamResolution(this.width, this.height);

  final int width;
  final int height;

  String get label => '${height}p';

  /// The resolution of [height], or null for a number this client does not
  /// offer: a file edited by hand keeps the default rather than an invented
  /// size.
  static StreamResolution? withHeight(int height) {
    for (final resolution in values) {
      if (resolution.height == height) return resolution;
    }
    return null;
  }
}

/// What a share and a camera are encoded at.
///
/// The bitrate defaults are Discord's web-client policy, not physics: the web
/// client is capped at 2500 kbps for a share and sends camera video smaller,
/// and a desktop client may use more. This object is the one home of those
/// numbers; everywhere else reads them from here.
final class StreamQualitySettings {
  const StreamQualitySettings({
    this.shareBitrate = defaultShareBitrate,
    this.cameraBitrate = defaultCameraBitrate,
    this.shareResolution = StreamResolution.p720,
    this.shareFrameRate = defaultShareFrameRate,
  });

  /// Discord's own default for a 720p30 share.
  static const defaultShareBitrate = 2500000;

  /// What a webcam picture is sent at: it carries far less detail than a
  /// desktop full of text.
  static const defaultCameraBitrate = 1200000;

  static const defaultShareFrameRate = 30;

  /// The frame rates a share can be sent at, the ones Discord offers.
  static const frameRates = [15, 30, 60];

  /// The bitrate of a share at 720p30; other shapes scale from it, see
  /// [shareEncodeBitrate]. Kept as the one slider rather than one per shape.
  final int shareBitrate;
  final int cameraBitrate;
  final StreamResolution shareResolution;
  final int shareFrameRate;

  /// What the share is actually encoded at: [shareBitrate] scaled by the
  /// pixels of the chosen shape against 720p, and by the frame rate less
  /// than proportionally, because consecutive pictures of a desktop share
  /// most of their content and a doubled rate does not need doubled bits.
  int get shareEncodeBitrate {
    final pixels =
        shareResolution.width *
        shareResolution.height /
        (StreamResolution.p720.width * StreamResolution.p720.height);
    final rate = switch (shareFrameRate) {
      15 => 0.7,
      60 => 1.5,
      _ => 1.0,
    };
    return (shareBitrate * pixels * rate).round();
  }

  /// Whether the numbers can be handed to an encoder. A bitrate that is not
  /// a positive number, or a frame rate off the list, is refused rather than
  /// clamped: the picker bounds the choice already, so anything else arrived
  /// by hand.
  bool get isValid =>
      shareBitrate > 0 &&
      cameraBitrate > 0 &&
      frameRates.contains(shareFrameRate);

  StreamQualitySettings copyWith({
    int? shareBitrate,
    int? cameraBitrate,
    StreamResolution? shareResolution,
    int? shareFrameRate,
  }) => StreamQualitySettings(
    shareBitrate: shareBitrate ?? this.shareBitrate,
    cameraBitrate: cameraBitrate ?? this.cameraBitrate,
    shareResolution: shareResolution ?? this.shareResolution,
    shareFrameRate: shareFrameRate ?? this.shareFrameRate,
  );

  Map<String, Object?> toJson() => {
    'share_bitrate': shareBitrate,
    'camera_bitrate': cameraBitrate,
    'share_resolution': shareResolution.height,
    'share_frame_rate': shareFrameRate,
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

    final frameRate = read('share_frame_rate', defaultShareFrameRate);
    return StreamQualitySettings(
      shareBitrate: read('share_bitrate', defaultShareBitrate),
      cameraBitrate: read('camera_bitrate', defaultCameraBitrate),
      shareResolution:
          StreamResolution.withHeight(read('share_resolution', 720)) ??
          StreamResolution.p720,
      shareFrameRate: frameRates.contains(frameRate)
          ? frameRate
          : defaultShareFrameRate,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StreamQualitySettings &&
      other.shareBitrate == shareBitrate &&
      other.cameraBitrate == cameraBitrate &&
      other.shareResolution == shareResolution &&
      other.shareFrameRate == shareFrameRate;

  @override
  int get hashCode =>
      Object.hash(shareBitrate, cameraBitrate, shareResolution, shareFrameRate);
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
