/// The interface adjustments this machine asked for.
///
/// Font scale, zoom and reduced motion are presentation concerns with no
/// protocol half: Discord keeps no such group in `PreloadedUserSettings`, so
/// they belong to whoever is sitting at this screen rather than to the
/// account signed in on it. The spellcheck switch lives beside them because
/// it is the same story: a local dictionary, consulted locally.
final class AccessibilitySettings {
  const AccessibilitySettings({
    this.fontScale = 1.0,
    this.zoom = 1.0,
    this.reducedMotion = false,
    this.spellcheck = true,
  });

  /// Multiplies the size of every piece of text.
  ///
  /// Clamped at construction and at every read so a hand-edited file cannot
  /// produce an unusable interface: half size and double size still leave
  /// something that can be read and navigated.
  final double fontScale;

  /// Multiplies the whole interface, laid out at the scaled size.
  final double zoom;

  /// Whether animations should hold their end state rather than play.
  final bool reducedMotion;

  /// Whether the composer underlines words the local dictionary does not
  /// know. On by default, which is Discord's own answer.
  final bool spellcheck;

  static const off = AccessibilitySettings();

  /// The smallest and largest each dial may go.
  static const minFontScale = 0.75;
  static const maxFontScale = 1.5;
  static const minZoom = 0.8;
  static const maxZoom = 1.4;

  /// The font scale clamped to its usable range.
  double get scaledFont => fontScale.clamp(minFontScale, maxFontScale);

  /// The zoom clamped to its usable range.
  double get scaledZoom => zoom.clamp(minZoom, maxZoom);

  AccessibilitySettings copyWith({
    double? fontScale,
    double? zoom,
    bool? reducedMotion,
    bool? spellcheck,
  }) => AccessibilitySettings(
    fontScale: fontScale ?? this.fontScale,
    zoom: zoom ?? this.zoom,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    spellcheck: spellcheck ?? this.spellcheck,
  );

  Map<String, Object?> toJson() => {
    'font_scale': fontScale,
    'zoom': zoom,
    'reduced_motion': reducedMotion,
    'spellcheck': spellcheck,
  };

  /// Reads stored settings, falling back per field.
  ///
  /// A file written by a newer build, or edited by hand, must not stop the
  /// client: an unreadable dial simply keeps its default.
  static AccessibilitySettings fromJson(Object? value) {
    if (value is! Map) return off;
    double readDial(String key, double fallback) {
      final held = value[key];
      return held is num ? held.toDouble() : fallback;
    }

    bool readSwitch(String key, {required bool fallback}) {
      final held = value[key];
      return held is bool ? held : fallback;
    }

    return AccessibilitySettings(
      fontScale: readDial('font_scale', 1.0),
      zoom: readDial('zoom', 1.0),
      reducedMotion: readSwitch('reduced_motion', fallback: false),
      spellcheck: readSwitch('spellcheck', fallback: true),
    );
  }
}

/// Where the dials are kept.
///
/// Local rather than on the account for the same reason as the settings
/// class above: the settings blob has no group for them, and a screen's
/// size belongs to the machine in front of it.
abstract interface class AccessibilityRepository {
  Future<AccessibilitySettings> load();
  Future<void> save(AccessibilitySettings settings);
}
