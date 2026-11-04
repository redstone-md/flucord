import 'dart:math';

import 'package:flutter/material.dart';

import '../domain/flucord_palette.dart';
import 'flucord_radius.dart';
import 'flucord_type.dart';

abstract final class FlucordTheme {
  // WCAG AA: 4.5:1 for text, 3:1 for icons and focus rings.
  static const textContrast = 4.5;
  static const _nonTextContrast = 3.0;
  static const _focusRingWidth = 2.0;

  /// How strongly a disabled control shows: buttons, icon buttons and menu
  /// rows all fade by this much.
  static const disabledAlpha = 0.38;

  /// How far the canvas card sits in from the window on the top, right and
  /// bottom, showing the rail colour around it. Its corner is
  /// [FlucordRadius.large].
  static const canvasInset = 8.0;

  /// Buttons, tabs and selects are this tall; a field is [_controlFieldHeight].
  static const _controlHeight = 32.0;
  static const _controlFieldHeight = 36.0;

  /// A field's text is the body role, 21 px a line.
  static const _fieldLineHeight = 21.0;

  /// The frame every button shares, whatever its colours: the control
  /// height, the padding, the [label] style and the control corner. The
  /// theme's filled button and every FlucordButton kind start from it.
  static ButtonStyle buttonFrame(TextStyle? label) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, _controlHeight)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
    textStyle: WidgetStatePropertyAll(label),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: FlucordRadius.control),
    ),
  );

  /// The frame of a field people type in: the inset fill, a 1 px border,
  /// the focus ring when focused and a danger border on an error. It sits
  /// darker than what is around it, so it reads as the place to type.
  ///
  /// The theme's fields take it at the control corner. Search and the
  /// composer pass their own [radius].
  static InputDecorationTheme recessedField(
    FlucordSurfaceTheme surfaces, {
    BorderRadius radius = FlucordRadius.control,
  }) {
    OutlineInputBorder outline(Color color, double width) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: color, width: width),
    );
    final resting = outline(surfaces.border, 1);
    final error = outline(surfaces.danger, _focusRingWidth);
    return InputDecorationTheme(
      filled: true,
      fillColor: surfaces.inset,
      isDense: true,
      border: resting,
      enabledBorder: resting,
      disabledBorder: resting,
      focusedBorder: outline(surfaces.focusRing, _focusRingWidth),
      errorBorder: error,
      focusedErrorBorder: error,
    );
  }

  /// How far a link moves from the accent toward the text colour. On a dark
  /// theme that is a lighter tint: #A497F8 beside the accent #8B7CF6.
  static const _linkTint = 0.25;

  static ThemeData get dark => fromPalette(FlucordPalette.dark);

  static ThemeData get light => fromPalette(FlucordPalette.light);

  /// Builds the whole theme from one palette.
  ///
  /// Every colour comes from here rather than from a constant, which is what
  /// lets an installed theme change them: a widget reaching for a hard-coded
  /// shade would keep Discord's own colour under somebody else's theme.
  static ThemeData fromPalette(FlucordPalette palette) => _build(
    brightness: palette.isDark ? Brightness.dark : Brightness.light,
    rail: Color(palette.rail),
    canvas: Color(palette.canvas),
    surface: Color(palette.surface),
    raised: Color(palette.raised),
    inset: Color(palette.inset),
    control: Color(palette.control),
    text: Color(palette.text),
    bodyText: Color(palette.bodyText),
    muted: Color(palette.muted),
    captionText: Color(palette.captionText),
    border: Color(palette.border),
    brand: Color(palette.brand),
    brandPressed: Color(palette.brandPressed),
    success: Color(palette.success),
    warning: Color(palette.warning),
    mention: Color(palette.mention),
    danger: Color(palette.danger),
    offline: Color(palette.offline),
  );

  /// The smallest move from [base] toward the theme's own [text] colour that
  /// reads at [ratio] on every one of [backgrounds].
  ///
  /// Computed rather than stored, so a theme file that never heard of these
  /// tokens still gets a link people can read, in its own hue. A colour that
  /// already reads stays as written. When even [text] cannot reach the ratio,
  /// [text] is the best the theme offers.
  static Color _readable(
    Color base, {
    required Color text,
    required List<Color> backgrounds,
    required double ratio,
  }) => towardText(
    base,
    text: text,
    backgrounds: backgrounds,
    reads: (shown, background) => contrast(shown, background) >= ratio,
  );

  /// The smallest move from [base] toward [text] for which [reads] holds on
  /// every one of [backgrounds], or [text] when nothing does. For a colour
  /// drawn with others around it, such as a name with an outline, where
  /// contrast alone does not say whether it reads.
  static Color towardText(
    Color base, {
    required Color text,
    required Iterable<Color> backgrounds,
    required bool Function(Color shown, Color background) reads,
  }) {
    for (var step = 0; step <= _readableSteps; step++) {
      final candidate = Color.lerp(base, text, step / _readableSteps)!;
      if (backgrounds.every((b) => reads(candidate, b))) return candidate;
    }
    return text;
  }

  static const _readableSteps = 100;

  /// The WCAG 2 contrast ratio of [foreground] drawn on [background].
  ///
  /// A theme file may give a colour alpha, so [foreground] is measured as it
  /// shows: mixed with [background].
  static double contrast(Color foreground, Color background) {
    final shown = Color.alphaBlend(foreground, background).computeLuminance();
    final under = background.computeLuminance();
    return (max(shown, under) + 0.05) / (min(shown, under) + 0.05);
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color rail,
    required Color canvas,
    required Color surface,
    required Color raised,
    required Color inset,
    required Color control,
    required Color text,
    required Color bodyText,
    required Color muted,
    required Color captionText,
    required Color border,
    required Color brand,
    required Color brandPressed,
    required Color success,
    required Color warning,
    required Color mention,
    required Color danger,
    required Color offline,
  }) {
    final backgrounds = [rail, canvas, surface, raised, inset, control];
    final focusRing = _readable(
      brand,
      text: text,
      backgrounds: backgrounds,
      ratio: _nonTextContrast,
    );
    Color readableText(Color base) => _readable(
      base,
      text: text,
      backgrounds: backgrounds,
      ratio: textContrast,
    );
    final errorText = readableText(danger);
    final focusSide = WidgetStateProperty.resolveWith<BorderSide?>(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: focusRing, width: _focusRingWidth)
          : null,
    );
    final scheme = ColorScheme(
      brightness: brightness,
      primary: brand,
      onPrimary: FlucordFixedColors.onFill,
      secondary: success,
      onSecondary: const Color(0xff051b10),
      // Widgets and Material's own fields draw error text in this, so it is the
      // readable error text. A danger fill takes `surfaces.danger` instead.
      error: errorText,
      onError: FlucordFixedColors.onFill,
      surface: surface,
      onSurface: text,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      dividerColor: border,
      fontFamily: FlucordType.family,
    );
    final textTheme = FlucordType.textTheme(
      base.textTheme,
    ).apply(bodyColor: text, displayColor: text);
    final surfaces = FlucordSurfaceTheme(
      rail: rail,
      canvas: canvas,
      surface: surface,
      raised: raised,
      inset: inset,
      control: control,
      text: text,
      bodyText: readableText(bodyText),
      muted: muted,
      captionText: readableText(captionText),
      border: border,
      brand: brand,
      brandPressed: brandPressed,
      success: success,
      warning: warning,
      mention: mention,
      danger: danger,
      offline: offline,
      link: readableText(Color.lerp(brand, text, _linkTint)!),
      errorText: errorText,
      accentIcon: focusRing,
      focusRing: focusRing,
    );
    return base.copyWith(
      canvasColor: canvas,
      cardColor: raised,
      hoverColor: text.withValues(alpha: 0.05),
      focusColor: brand.withValues(alpha: 0.24),
      textTheme: textTheme,
      iconTheme: IconThemeData(color: muted, size: 19),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return muted.withValues(alpha: disabledAlpha);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)) {
              return text;
            }
            return muted;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return brand.withValues(alpha: 0.2);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return text.withValues(alpha: 0.08);
            }
            return null;
          }),
          side: focusSide,
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: FlucordRadius.control),
          ),
        ),
      ),
      // The primary button is light, with the label in the rail colour:
      // white on the violet accent does not reach 4.5:1.
      filledButtonTheme: FilledButtonThemeData(
        style: buttonFrame(textTheme.labelLarge).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? text.withValues(alpha: disabledAlpha)
                : text,
          ),
          foregroundColor: WidgetStatePropertyAll(rail),
          side: focusSide,
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: ButtonStyle(side: focusSide)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(side: focusSide),
      ),
      // Every dialog is a FlucordDialog, which takes its frame from here:
      // one barrier, one background and one corner, in every theme. It sits
      // one layer up, like a menu.
      dialogTheme: DialogThemeData(
        barrierColor: Colors.black.withValues(alpha: 0.6),
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black,
        elevation: 24,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: FlucordRadius.overlay,
          side: BorderSide(color: border),
        ),
        titleTextStyle: FlucordTextRole.heading.style.copyWith(color: text),
        contentTextStyle: FlucordTextRole.label.style.copyWith(color: muted),
      ),
      // Every menu opens one layer up from where it was opened, the same
      // frame a popover has. The rows are FlucordMenuItem.
      popupMenuTheme: PopupMenuThemeData(
        color: raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: FlucordRadius.overlay,
          side: BorderSide(color: border),
        ),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        labelTextStyle: WidgetStatePropertyAll(
          FlucordTextRole.label.style.copyWith(color: text),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: rail,
          borderRadius: FlucordRadius.small,
        ),
        textStyle: FlucordTextRole.caption.style.copyWith(color: text),
        waitDuration: const Duration(milliseconds: 450),
      ),
      // Fields are recessed: darker than what they sit on, with a thin
      // border, so it is plain where to type.
      inputDecorationTheme: recessedField(surfaces).copyWith(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: (_controlFieldHeight - _fieldLineHeight) / 2,
        ),
        hintStyle: FlucordTextRole.body.style.copyWith(color: captionText),
        errorStyle: FlucordTextRole.caption.style.copyWith(color: errorText),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: brand,
        inactiveTrackColor: text.withValues(alpha: 0.1),
        thumbColor: FlucordFixedColors.onFill,
        overlayColor: brand.withValues(alpha: 0.24),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      extensions: [surfaces],
    );
  }
}

/// Colours that are the same in every theme, because what lies under them
/// is not the theme's: a strong colour fill, a photo or a video.
abstract final class FlucordFixedColors {
  /// Text and marks on a strong fill: the accent, danger, a space's colour.
  static const onFill = Color(0xFFFFFFFF);

  /// Text and marks on a light fill, such as the warning amber, where white
  /// would not read.
  static const onLightFill = Color(0xFF000000);

  /// Behind a video, where the picture does not reach.
  static const media = Color(0xFF000000);

  /// The round backing of a control drawn over a picture.
  static const scrim = Color.fromRGBO(0, 0, 0, 0.55);

  /// Darkens a whole picture so a label drawn across it reads.
  static const pictureShade = Color.fromRGBO(0, 0, 0, 0.42);

  /// The bar of controls over a playing video.
  static const mediaControls = Color.fromRGBO(0, 0, 0, 0.82);

  /// The star on a favourite.
  static const favourite = Color(0xFFF0B232);

  /// The shadow under something that floats over the interface, such as the
  /// profile card.
  static const shadow = Color(0xFF000000);
}

@immutable
final class FlucordSurfaceTheme extends ThemeExtension<FlucordSurfaceTheme> {
  const FlucordSurfaceTheme({
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
    required this.link,
    required this.errorText,
    required this.accentIcon,
    required this.focusRing,
  });

  final Color rail;
  final Color canvas;
  final Color surface;
  final Color raised;
  final Color inset;
  final Color control;

  /// Titles and names: the brightest text tier.
  final Color text;

  /// Message text. Reaches 4.5:1 on every background of the theme.
  final Color bodyText;

  /// Secondary text, and the default icon colour.
  final Color muted;

  /// Captions and placeholders: the faintest text tier. Reaches 4.5:1 on
  /// every background of the theme.
  final Color captionText;

  /// Lines between areas. May be see-through.
  final Color border;
  final Color brand;
  final Color brandPressed;
  final Color success;
  final Color warning;
  final Color mention;
  final Color danger;
  final Color offline;

  /// Link text: the accent, a step toward the text colour. Reaches 4.5:1 on
  /// every background of the theme.
  final Color link;

  /// Error text. Reaches 4.5:1 on every background of the theme.
  final Color errorText;

  /// An icon in the accent colour, such as Send. Reaches 3:1.
  final Color accentIcon;

  /// The ring on a focused control. Reaches 3:1.
  final Color focusRing;

  @override
  FlucordSurfaceTheme copyWith({
    Color? rail,
    Color? canvas,
    Color? surface,
    Color? raised,
    Color? inset,
    Color? control,
    Color? text,
    Color? bodyText,
    Color? muted,
    Color? captionText,
    Color? border,
    Color? brand,
    Color? brandPressed,
    Color? success,
    Color? warning,
    Color? mention,
    Color? danger,
    Color? offline,
    Color? link,
    Color? errorText,
    Color? accentIcon,
    Color? focusRing,
  }) => FlucordSurfaceTheme(
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
    link: link ?? this.link,
    errorText: errorText ?? this.errorText,
    accentIcon: accentIcon ?? this.accentIcon,
    focusRing: focusRing ?? this.focusRing,
  );

  @override
  FlucordSurfaceTheme lerp(
    covariant ThemeExtension<FlucordSurfaceTheme>? other,
    double t,
  ) {
    if (other is! FlucordSurfaceTheme) return this;
    return FlucordSurfaceTheme(
      rail: Color.lerp(rail, other.rail, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      inset: Color.lerp(inset, other.inset, t)!,
      control: Color.lerp(control, other.control, t)!,
      text: Color.lerp(text, other.text, t)!,
      bodyText: Color.lerp(bodyText, other.bodyText, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      captionText: Color.lerp(captionText, other.captionText, t)!,
      border: Color.lerp(border, other.border, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandPressed: Color.lerp(brandPressed, other.brandPressed, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      mention: Color.lerp(mention, other.mention, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      link: Color.lerp(link, other.link, t)!,
      errorText: Color.lerp(errorText, other.errorText, t)!,
      accentIcon: Color.lerp(accentIcon, other.accentIcon, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
    );
  }
}

extension FlucordThemeContext on BuildContext {
  FlucordSurfaceTheme get surfaces =>
      Theme.of(this).extension<FlucordSurfaceTheme>()!;
}

/// Fills drawn from a role rather than stored, so a theme never sets them.
extension FlucordFills on FlucordSurfaceTheme {
  /// A selected row or tab, a secondary button, a close button: the text
  /// colour at 6%, which is white at 6% in the dark theme.
  Color get quietFill => text.withValues(alpha: 0.06);

  /// The accent at 18%, behind accent text: the APP tag beside a bot's name.
  Color get brandTint => brand.withValues(alpha: 0.18);

  /// Every fill a piece of text can end up on.
  List<Color> get backgrounds => [rail, canvas, surface, raised, inset, control];
}
