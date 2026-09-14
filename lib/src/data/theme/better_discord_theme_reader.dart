import '../../domain/flucord_palette.dart';

/// Reads the colours out of a theme written for BetterDiscord.
///
/// A BD theme is CSS, and most of it — selectors, layout overrides, animations
/// — describes a DOM that Flucord does not have. What every such theme does
/// have is a block of custom properties naming Discord's own colours, and
/// those are exactly the colours Flucord draws with under different names. So
/// the variables are read and the rest is left alone rather than half-applied:
/// a theme that visibly did some of what it promised would be worse than one
/// that plainly did the colours.
abstract final class BetterDiscordThemeReader {
  /// Reads `//META{...}*//` — the header BD requires on every theme.
  static Map<String, String> readMeta(String source) {
    final match = RegExp(r'/\*\*(.*?)\*/', dotAll: true).firstMatch(source);
    if (match == null) return const {};
    final meta = <String, String>{};
    for (final line in RegExp(
      r'@(\w+)\s+([^\r\n]*)',
    ).allMatches(match.group(1) ?? '')) {
      final key = line.group(1);
      final value = line.group(2)?.trim();
      if (key != null && value != null && value.isNotEmpty) meta[key] = value;
    }
    return meta;
  }

  /// Every `--name: value` the file declares.
  ///
  /// Later declarations win, which is what the cascade does: a theme that sets
  /// a variable once at the top and again inside `.theme-dark` means the
  /// second.
  static Map<String, String> readVariables(String source) {
    final variables = <String, String>{};
    for (final match in RegExp(
      r'--([A-Za-z0-9_-]+)\s*:\s*([^;{}]+)[;}]',
    ).allMatches(source)) {
      final name = match.group(1);
      final value = match.group(2)?.trim();
      if (name != null && value != null && value.isNotEmpty) {
        variables[name] = value;
      }
    }
    return variables;
  }

  /// Turns a BD theme into a palette, keeping [fallback] for anything it does
  /// not name.
  ///
  /// Most themes restate a handful of backgrounds and leave the rest to
  /// Discord's defaults, so a reader that demanded the full set would refuse
  /// almost everything it was given.
  static FlucordPalette readPalette(
    String source, {
    FlucordPalette fallback = FlucordPalette.dark,
  }) {
    final variables = readVariables(source);
    int? pick(List<String> names) {
      for (final name in names) {
        final resolved = resolve(variables[name], variables);
        if (resolved != null) return resolved;
      }
      return null;
    }

    final canvas = pick(_canvas);
    return fallback.copyWith(
      // The background decides light from dark, and only when the theme said
      // nothing about it does the fallback's own answer stand.
      isDark: canvas == null ? fallback.isDark : _isDark(canvas),
      canvas: canvas,
      rail: pick(_rail),
      surface: pick(_surface),
      raised: pick(_raised),
      inset: pick(_inset),
      control: pick(_control),
      text: pick(_text),
      muted: pick(_muted),
      border: pick(_border),
      brand: pick(_brand),
      success: pick(_success),
      warning: pick(_warning),
      danger: pick(_danger),
      mention: pick(_mention),
      offline: pick(_offline),
    );
  }

  /// Resolves one value to an ARGB integer.
  ///
  /// `var(--other)` is followed once. Themes chain aliases a level or two
  /// deep, and a reader that did not follow them would read a colour as
  /// absent for every theme written the modern way.
  static int? resolve(
    String? value,
    Map<String, String> variables, [
    int depth = 0,
  ]) {
    if (value == null || depth > 4) return null;
    final trimmed = value.trim();
    final alias = RegExp(
      r'var\(\s*--([A-Za-z0-9_-]+)\s*(?:,([^)]*))?\)',
    ).firstMatch(trimmed);
    if (alias != null) {
      final name = alias.group(1);
      final resolved = resolve(variables[name], variables, depth + 1);
      if (resolved != null) return resolved;
      // A `var(--x, #fff)` carries its own fallback, which is what a theme
      // relies on when the variable is one Discord stopped shipping.
      return resolve(alias.group(2), variables, depth + 1);
    }
    return parseColour(trimmed);
  }

  /// `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, and the bare
  /// `r, g, b` triples Discord's own variables are written as.
  static int? parseColour(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('#')) return _parseHex(text.substring(1));

    final rgb = RegExp(
      r'rgba?\(([^)]*)\)',
      caseSensitive: false,
    ).firstMatch(text);
    final body = rgb?.group(1) ?? text;
    final parts = body
        .split(RegExp(r'[,\s/]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 3) return null;
    final channels = <int>[];
    for (var index = 0; index < 3; index++) {
      final channel = _channel(parts[index]);
      if (channel == null) return null;
      channels.add(channel);
    }
    var alpha = 255;
    if (parts.length > 3) {
      final value = double.tryParse(parts[3].replaceAll('%', ''));
      if (value != null) {
        alpha = (parts[3].contains('%') ? value * 2.55 : value * 255)
            .round()
            .clamp(0, 255);
      }
    }
    return (alpha << 24) |
        (channels[0] << 16) |
        (channels[1] << 8) |
        channels[2];
  }

  static int? _channel(String part) {
    final value = double.tryParse(part.replaceAll('%', ''));
    if (value == null) return null;
    return (part.contains('%') ? value * 2.55 : value).round().clamp(0, 255);
  }

  static int? _parseHex(String digits) {
    final clean = digits.trim();
    final expanded = switch (clean.length) {
      3 => clean.split('').map((digit) => '$digit$digit').join(),
      4 => clean.split('').map((digit) => '$digit$digit').join(),
      _ => clean,
    };
    if (expanded.length != 6 && expanded.length != 8) return null;
    final parsed = int.tryParse(expanded, radix: 16);
    if (parsed == null) return null;
    if (expanded.length == 6) return 0xff000000 | parsed;
    // CSS writes the alpha last and Flutter wants it first.
    return ((parsed & 0xff) << 24) | (parsed >> 8);
  }

  /// Whether text on this background should be light.
  ///
  /// Rec. 601 luma rather than a plain average: the eye reads green as far
  /// brighter than blue, and averaging calls a saturated blue light enough for
  /// black text when it is not.
  static bool _isDark(int argb) {
    final red = (argb >> 16) & 0xff;
    final green = (argb >> 8) & 0xff;
    final blue = argb & 0xff;
    return (0.299 * red + 0.587 * green + 0.114 * blue) < 128;
  }

  // The variable names, oldest first within each group: Discord renamed these
  // twice and themes in the wild are written against all three generations.
  static const _canvas = [
    'background-primary',
    'bg-base-primary',
    'primary-630',
  ];
  static const _surface = [
    'background-secondary',
    'bg-base-secondary',
    'primary-660',
  ];
  static const _rail = [
    'background-tertiary',
    'bg-base-tertiary',
    'primary-800',
  ];
  static const _raised = [
    'background-floating',
    'bg-surface-raised',
    'background-secondary-alt',
  ];
  static const _inset = ['background-modifier-selected', 'bg-surface-overlay'];
  static const _control = ['background-modifier-hover', 'input-background'];
  static const _text = ['text-normal', 'text-default', 'header-primary'];
  static const _muted = ['text-muted', 'text-secondary', 'channels-default'];
  static const _border = ['background-modifier-accent', 'border-subtle'];
  static const _brand = ['brand-experiment', 'brand-500', 'blurple'];
  static const _success = ['status-green', 'green-360', 'text-positive'];
  static const _warning = ['status-yellow', 'yellow-300', 'text-warning'];
  static const _danger = ['status-red', 'red-400', 'text-danger'];
  static const _mention = ['status-danger', 'red-500', 'mention-foreground'];
  static const _offline = ['status-grey', 'primary-400'];
}
