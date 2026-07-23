import 'package:flutter/material.dart';

abstract final class FlucordColors {
  static const brand = Color(0xff5865f2);
  static const brandPressed = Color(0xff4752c4);
  static const success = Color(0xff23a55a);
  static const warning = Color(0xfff0b232);
  static const mention = Color(0xfff23f42);
  static const danger = Color(0xffda373c);
  static const offline = Color(0xff80848e);

  static const darkRail = Color(0xff1e1f22);
  static const darkCanvas = Color(0xff313338);
  static const darkSurface = Color(0xff2b2d31);
  static const darkRaised = Color(0xff3f4147);
  static const darkInset = Color(0xff232428);
  static const darkControl = Color(0xff383a40);

  static const lightRail = Color(0xffe3e5e8);
  static const lightCanvas = Color(0xffffffff);
  static const lightSurface = Color(0xfff2f3f5);
  static const lightRaised = Color(0xffdfe3e8);
  static const lightInset = Color(0xffebedef);
  static const lightControl = Color(0xffebedef);
}

abstract final class FlucordTheme {
  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    rail: FlucordColors.darkRail,
    canvas: FlucordColors.darkCanvas,
    surface: FlucordColors.darkSurface,
    raised: FlucordColors.darkRaised,
    inset: FlucordColors.darkInset,
    control: FlucordColors.darkControl,
    text: const Color(0xfff2f3f5),
    muted: const Color(0xff949ba4),
    border: const Color(0xff3f4147),
  );

  static ThemeData get light => _build(
    brightness: Brightness.light,
    rail: FlucordColors.lightRail,
    canvas: FlucordColors.lightCanvas,
    surface: FlucordColors.lightSurface,
    raised: FlucordColors.lightRaised,
    inset: FlucordColors.lightInset,
    control: FlucordColors.lightControl,
    text: const Color(0xff313338),
    muted: const Color(0xff5c5e66),
    border: const Color(0xffd7d9dc),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color rail,
    required Color canvas,
    required Color surface,
    required Color raised,
    required Color inset,
    required Color control,
    required Color text,
    required Color muted,
    required Color border,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: FlucordColors.brand,
      onPrimary: Colors.white,
      secondary: FlucordColors.success,
      onSecondary: const Color(0xff051b10),
      error: FlucordColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      dividerColor: border,
      fontFamily: 'Bahnschrift',
    );
    return base.copyWith(
      canvasColor: canvas,
      cardColor: raised,
      hoverColor: text.withValues(alpha: 0.05),
      focusColor: FlucordColors.brand.withValues(alpha: 0.24),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      iconTheme: IconThemeData(color: muted, size: 19),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return muted.withValues(alpha: 0.38);
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
              return FlucordColors.brand.withValues(alpha: 0.2);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return text.withValues(alpha: 0.08);
            }
            return null;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return FlucordColors.brand.withValues(alpha: 0.38);
            }
            return states.contains(WidgetState.pressed)
                ? FlucordColors.brandPressed
                : FlucordColors.brand;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: rail,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(color: text, fontSize: 12),
        waitDuration: const Duration(milliseconds: 450),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: control,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: FlucordColors.brand),
        ),
      ),
      extensions: [
        FlucordSurfaceTheme(
          rail: rail,
          canvas: canvas,
          surface: surface,
          raised: raised,
          inset: inset,
          control: control,
          muted: muted,
          border: border,
        ),
      ],
    );
  }
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
    required this.muted,
    required this.border,
  });

  final Color rail;
  final Color canvas;
  final Color surface;
  final Color raised;
  final Color inset;
  final Color control;
  final Color muted;
  final Color border;

  @override
  FlucordSurfaceTheme copyWith({
    Color? rail,
    Color? canvas,
    Color? surface,
    Color? raised,
    Color? inset,
    Color? control,
    Color? muted,
    Color? border,
  }) => FlucordSurfaceTheme(
    rail: rail ?? this.rail,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    inset: inset ?? this.inset,
    control: control ?? this.control,
    muted: muted ?? this.muted,
    border: border ?? this.border,
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
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

extension FlucordThemeContext on BuildContext {
  FlucordSurfaceTheme get surfaces =>
      Theme.of(this).extension<FlucordSurfaceTheme>()!;
}
