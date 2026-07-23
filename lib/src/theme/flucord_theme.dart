import 'package:flutter/material.dart';

abstract final class FlucordColors {
  static const signal = Color(0xff4c9b72);
  static const signalDark = Color(0xff307354);
  static const copper = Color(0xffb87945);
  static const danger = Color(0xffb85c5c);
  static const darkCanvas = Color(0xff101213);
  static const darkSurface = Color(0xff181a1b);
  static const darkRaised = Color(0xff202324);
  static const darkInset = Color(0xff0c0e0f);
  static const lightCanvas = Color(0xfff3f3f0);
  static const lightSurface = Color(0xfffafaf8);
  static const lightRaised = Color(0xffffffff);
  static const lightInset = Color(0xffe9e9e5);
}

abstract final class FlucordTheme {
  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    canvas: FlucordColors.darkCanvas,
    surface: FlucordColors.darkSurface,
    raised: FlucordColors.darkRaised,
    inset: FlucordColors.darkInset,
    text: const Color(0xffe4e5e3),
    muted: const Color(0xff989d99),
    border: const Color(0xff303435),
  );

  static ThemeData get light => _build(
    brightness: Brightness.light,
    canvas: FlucordColors.lightCanvas,
    surface: FlucordColors.lightSurface,
    raised: FlucordColors.lightRaised,
    inset: FlucordColors.lightInset,
    text: const Color(0xff202322),
    muted: const Color(0xff656b67),
    border: const Color(0xffd7d8d3),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color canvas,
    required Color surface,
    required Color raised,
    required Color inset,
    required Color text,
    required Color muted,
    required Color border,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: FlucordColors.signal,
      onPrimary: Colors.white,
      secondary: FlucordColors.copper,
      onSecondary: Colors.white,
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
      focusColor: FlucordColors.signal.withValues(alpha: 0.2),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      iconTheme: IconThemeData(color: muted, size: 19),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: raised,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(color: text, fontSize: 12),
        waitDuration: const Duration(milliseconds: 450),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inset,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: FlucordColors.signal),
        ),
      ),
      extensions: [
        FlucordSurfaceTheme(
          canvas: canvas,
          surface: surface,
          raised: raised,
          inset: inset,
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
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.inset,
    required this.muted,
    required this.border,
  });

  final Color canvas;
  final Color surface;
  final Color raised;
  final Color inset;
  final Color muted;
  final Color border;

  @override
  FlucordSurfaceTheme copyWith({
    Color? canvas,
    Color? surface,
    Color? raised,
    Color? inset,
    Color? muted,
    Color? border,
  }) => FlucordSurfaceTheme(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    inset: inset ?? this.inset,
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
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      inset: Color.lerp(inset, other.inset, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

extension FlucordThemeContext on BuildContext {
  FlucordSurfaceTheme get surfaces =>
      Theme.of(this).extension<FlucordSurfaceTheme>()!;
}
