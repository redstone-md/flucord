/// The profile effect somebody wears: Discord's `profile_effect` on a user
/// profile or a server profile.
final class ProfileEffect {
  const ProfileEffect({required this.skuId, this.expiresAt});

  /// Its kind among the items of a shop product.
  static const collectibleType = 1;

  /// Reads a `profile_effect` object, which names the effect by its
  /// `sku_id`. Null for one without.
  static ProfileEffect? fromJson(Object? json) {
    if (json is! Map) return null;
    final skuId = json['sku_id'];
    if (skuId is! String || skuId.isEmpty) return null;
    final expiresAt = json['expires_at'];
    return ProfileEffect(
      skuId: skuId,
      // Unix seconds, or null for an effect that does not expire.
      expiresAt: expiresAt is int
          ? DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000, isUtc: true)
          : null,
    );
  }

  /// What the shop sells the effect as, and what it describes it by.
  final String skuId;
  final DateTime? expiresAt;

  bool isWornAt(DateTime now) => expiresAt?.isAfter(now) ?? true;

  @override
  bool operator ==(Object other) =>
      other is ProfileEffect &&
      other.skuId == skuId &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(skuId, expiresAt);
}

/// How an effect looks: the effect item of the shop's product for it, as
/// Discord's client reads it from `GET /collectibles-products/{sku}`.
final class ProfileEffectConfig {
  const ProfileEffectConfig({required this.layers, this.stillSrc});

  /// Reads the effect item. Null for one with nothing to draw.
  static ProfileEffectConfig? fromJson(Map<String, Object?> json) {
    final config = ProfileEffectConfig(
      stillSrc:
          _text(json['reducedMotionSrc']) ??
          _text(json['staticFrameSrc']) ??
          _text(json['thumbnailPreviewSrc']),
      layers: [
        for (final layer in json['effects'] as List? ?? const [])
          if (layer is Map)
            ?ProfileEffectLayer.fromJson(layer.cast<String, Object?>()),
      ],
    );
    return config.layers.isEmpty && config.stillSrc == null ? null : config;
  }

  /// The width, in Discord's units, that layer positions and sizes are
  /// given in. The effect is scaled to the card's width.
  static const canvasWidth = 450.0;

  /// What reduced motion draws in place of the layers.
  final String? stillSrc;

  /// In Discord's order, which is the order they are drawn in.
  final List<ProfileEffectLayer> layers;

  /// The layers shown [elapsed] after the effect started, lowest first.
  List<ProfileEffectLayer> layersAt(Duration elapsed) => [
    for (final layer in layers)
      if (layer.isShownAt(elapsed.inMilliseconds)) layer,
  ]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

  /// When, after [elapsed], the shown layers change next, or null when they
  /// never change again.
  Duration? nextChangeAfter(Duration elapsed) {
    final changes = [
      for (final layer in layers)
        ?layer.nextChangeAfter(elapsed.inMilliseconds),
    ];
    if (changes.isEmpty) return null;
    return Duration(milliseconds: changes.reduce((a, b) => a < b ? a : b));
  }

  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

/// One animated picture of an effect, placed on the effect's canvas.
///
/// A layer appears at [start]. One that does not loop shows for [duration]
/// and then goes. One that loops shows for [duration], hides for
/// [loopDelay], and starts again.
final class ProfileEffectLayer {
  const ProfileEffectLayer({
    required this.src,
    required this.width,
    required this.height,
    this.loop = false,
    this.duration = 0,
    this.start = 0,
    this.loopDelay = 0,
    this.x = 0,
    this.y = 0,
    this.zIndex = 0,
    this.randomizedSources = const [],
  });

  static ProfileEffectLayer? fromJson(Map<String, Object?> json) {
    final src = json['src'];
    if (src is! String || src.isEmpty) return null;
    final position = json['position'];
    int number(Object? value) => value is num ? value.toInt() : 0;
    return ProfileEffectLayer(
      src: src,
      width: number(json['width']),
      height: number(json['height']),
      loop: json['loop'] == true,
      duration: number(json['duration']),
      start: number(json['start']),
      loopDelay: number(json['loopDelay']),
      x: position is Map ? number(position['x']) : 0,
      y: position is Map ? number(position['y']) : 0,
      zIndex: number(json['zIndex']),
      randomizedSources: [
        for (final source in json['randomizedSources'] as List? ?? const [])
          if (source is Map && source['src'] is String) source['src'] as String,
      ],
    );
  }

  final String src;
  final int width;
  final int height;
  final bool loop;

  /// Milliseconds, as are [start] and [loopDelay].
  final int duration;
  final int start;
  final int loopDelay;
  final int x;
  final int y;
  final int zIndex;

  /// Pictures Discord picks one of in place of [src].
  final List<String> randomizedSources;

  bool isShownAt(int ms) {
    if (ms < start) return false;
    final since = ms - start;
    if (!loop) return since < duration;
    final period = duration + loopDelay;
    return period <= 0 || since % period < duration;
  }

  int? nextChangeAfter(int ms) {
    if (ms < start) return start;
    final since = ms - start;
    if (!loop) return since < duration ? start + duration : null;
    final period = duration + loopDelay;
    if (loopDelay <= 0 || period <= 0) return null;
    final phase = since % period;
    final cycleStart = ms - phase;
    return phase < duration ? cycleStart + duration : cycleStart + period;
  }
}
