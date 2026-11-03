/// Every colour the client draws with, as data rather than as constants.
///
/// The surfaces are named for what they are in the layout rather than for a
/// shade, because a light theme inverts the shades and a name like `grey900`
/// would then be a lie. They are also the names Discord's own CSS variables
/// map onto, which is what makes importing a theme written for it possible at
/// all.
final class FlucordPalette {
  const FlucordPalette({
    required this.isDark,
    required this.rail,
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.inset,
    required this.control,
    required this.text,
    required this.bodyText,
    required this.muted,
    required this.captionText,
    required this.border,
    required this.brand,
    required this.brandPressed,
    required this.success,
    required this.warning,
    required this.mention,
    required this.danger,
    required this.offline,
  });

  /// Whether the client should treat this as a dark theme.
  ///
  /// Not inferred from the background on every read: a theme is free to be
  /// dark with a pale sidebar, and guessing would flip the icon set on it.
  final bool isDark;

  /// The server strip, darkest in Discord's own scheme.
  final int rail;

  /// Behind the message list.
  final int canvas;

  /// Panels beside the canvas: the channel list, the member list.
  final int surface;

  /// Something lifted off the surface — a card, a popover.
  final int raised;

  /// Something pressed into it: a code block, a search field.
  final int inset;

  /// A control's own background.
  final int control;

  /// Text has four tiers, brightest first: [text] for titles and names,
  /// [bodyText] for message text, [muted] for secondary text, and
  /// [captionText] for captions and placeholders.
  final int text;
  final int bodyText;
  final int muted;
  final int captionText;

  /// Lines between areas. May carry alpha, so it lightens whatever is under
  /// it by the same step.
  final int border;

  final int brand;
  final int brandPressed;
  final int success;
  final int warning;
  final int mention;
  final int danger;
  final int offline;

  /// Neutral cool greys a few percent apart, with one violet accent. Red
  /// marks danger and unread counts, green marks voice and online.
  static const dark = FlucordPalette(
    isDark: true,
    rail: 0xff08090a,
    canvas: 0xff111113,
    surface: 0xff111113,
    raised: 0xff1b1b1e,
    inset: 0xff0c0c0e,
    control: 0xff1b1b1e,
    text: 0xffeeeef0,
    bodyText: 0xffc8c8ce,
    muted: 0xff8e8e96,
    captionText: 0xff616168,
    border: 0x12ffffff,
    brand: 0xff8b7cf6,
    brandPressed: 0xff7a6ae6,
    success: 0xff46a758,
    warning: 0xffe2a336,
    mention: 0xffe5484d,
    danger: 0xffe5484d,
    offline: 0xff6f6e77,
  );

  static const light = FlucordPalette(
    isDark: false,
    rail: 0xffe3e5e8,
    canvas: 0xffffffff,
    surface: 0xfff2f3f5,
    raised: 0xffdfe3e8,
    inset: 0xffebedef,
    control: 0xffebedef,
    text: 0xff313338,
    // The light theme keeps its two tiers until it gets its own design.
    bodyText: 0xff313338,
    muted: 0xff5c5e66,
    captionText: 0xff5c5e66,
    border: 0xffd7d9dc,
    brand: 0xff5865f2,
    brandPressed: 0xff4752c4,
    success: 0xff23a55a,
    warning: 0xfff0b232,
    mention: 0xfff23f42,
    danger: 0xffda373c,
    offline: 0xff80848e,
  );

  FlucordPalette copyWith({
    bool? isDark,
    int? rail,
    int? canvas,
    int? surface,
    int? raised,
    int? inset,
    int? control,
    int? text,
    int? bodyText,
    int? muted,
    int? captionText,
    int? border,
    int? brand,
    int? brandPressed,
    int? success,
    int? warning,
    int? mention,
    int? danger,
    int? offline,
  }) => FlucordPalette(
    isDark: isDark ?? this.isDark,
    rail: rail ?? this.rail,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    inset: inset ?? this.inset,
    control: control ?? this.control,
    text: text ?? this.text,
    bodyText: bodyText ?? this.bodyText,
    muted: muted ?? this.muted,
    captionText: captionText ?? this.captionText,
    border: border ?? this.border,
    brand: brand ?? this.brand,
    brandPressed: brandPressed ?? this.brandPressed,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    mention: mention ?? this.mention,
    danger: danger ?? this.danger,
    offline: offline ?? this.offline,
  );

  Map<String, Object?> toJson() => {
    'is_dark': isDark,
    'rail': rail,
    'canvas': canvas,
    'surface': surface,
    'raised': raised,
    'inset': inset,
    'control': control,
    'text': text,
    'body_text': bodyText,
    'muted': muted,
    'caption_text': captionText,
    'border': border,
    'brand': brand,
    'brand_pressed': brandPressed,
    'success': success,
    'warning': warning,
    'mention': mention,
    'danger': danger,
    'offline': offline,
  };

  /// Reads a stored palette, filling anything absent from [fallback].
  ///
  /// Per field rather than all-or-nothing: a theme that only restates the
  /// backgrounds is a normal thing to write, and refusing it because it said
  /// nothing about the warning colour would be refusing most themes.
  ///
  /// Reads `#rgb`, `#rrggbb` or `#aarrggbb`, or null when it is none of them.
  ///
  /// Alpha first when it is given, and opaque when it is not: a theme that
  /// left it out and got a transparent surface would look broken in a way
  /// that is very hard to attribute to the file.
  static int? parseHexColour(String value) {
    final digits = value.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(digits)) return null;
    final expanded = switch (digits.length) {
      3 => 'ff${digits[0] * 2}${digits[1] * 2}${digits[2] * 2}',
      6 => 'ff$digits',
      8 => digits,
      _ => null,
    };
    return expanded == null ? null : int.tryParse(expanded, radix: 16);
  }

  static FlucordPalette fromJson(
    Object? value, {
    FlucordPalette fallback = dark,
  }) {
    if (value is! Map) return fallback;
    int read(String key, int Function(FlucordPalette) of) {
      final held = value[key];
      if (held is int) return held;
      // Hex too, because a theme is written by hand. Nobody types
      // 4280358679 when they mean #1c1917, and a file that only accepts the
      // decimal form is a file people edit with a calculator open.
      if (held is String) return parseHexColour(held) ?? of(fallback);
      return of(fallback);
    }

    final isDark = value['is_dark'];
    return FlucordPalette(
      isDark: isDark is bool ? isDark : fallback.isDark,
      rail: read('rail', (p) => p.rail),
      canvas: read('canvas', (p) => p.canvas),
      surface: read('surface', (p) => p.surface),
      raised: read('raised', (p) => p.raised),
      inset: read('inset', (p) => p.inset),
      control: read('control', (p) => p.control),
      text: read('text', (p) => p.text),
      bodyText: read('body_text', (p) => p.bodyText),
      muted: read('muted', (p) => p.muted),
      captionText: read('caption_text', (p) => p.captionText),
      border: read('border', (p) => p.border),
      brand: read('brand', (p) => p.brand),
      brandPressed: read('brand_pressed', (p) => p.brandPressed),
      success: read('success', (p) => p.success),
      warning: read('warning', (p) => p.warning),
      mention: read('mention', (p) => p.mention),
      danger: read('danger', (p) => p.danger),
      offline: read('offline', (p) => p.offline),
    );
  }
}

/// A theme the user installed.
final class InstalledTheme {
  const InstalledTheme({
    required this.id,
    required this.name,
    required this.palette,
    this.author = '',
    this.version = '',
    this.description = '',
    this.source = ThemeSource.flucord,
  });

  /// What the file is called, which is what makes a theme replaceable by
  /// dropping the same name in again.
  final String id;

  final String name;
  final FlucordPalette palette;
  final String author;
  final String version;
  final String description;
  final ThemeSource source;
}

/// Where a theme came from, because it changes what can be promised about it.
enum ThemeSource {
  /// Written for Flucord: every colour it names is a colour Flucord draws.
  flucord,

  /// A BetterDiscord theme, of which only the colour variables were read.
  betterDiscord,
}
