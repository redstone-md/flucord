import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails when any text on screen is drawn at a size off the type scale.
///
/// Reads what is laid out, so it sees each size as the user gets it, after
/// the theme and every inherited style. Icons are glyphs of an icon font and
/// take the icon's size, so they are left out. Pictures of emoji drawn as
/// text are left out the same way, by passing their [glyphs].
void expectTextOnTypeScale(
  WidgetTester tester, {
  Set<String> glyphs = const {},
}) {
  final off = <String>[];
  // A widget inside text, such as a custom emoji, is its own render object.
  void visit(InlineSpan span, double inherited) {
    if (span is! TextSpan) return;
    final style = span.style;
    final size = style?.fontSize ?? inherited;
    final text = span.text;
    final isIcon = style?.fontFamily?.contains('Icons') ?? false;
    if (text != null &&
        text.trim().isNotEmpty &&
        !isIcon &&
        !glyphs.contains(text) &&
        !FlucordType.sizes.contains(size)) {
      off.add('$size px: "$text"');
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, size);
    }
  }

  for (final object in tester.allRenderObjects) {
    final text = switch (object) {
      RenderParagraph(:final text) => text,
      RenderEditable(:final text?) => text,
      _ => null,
    };
    // 14 px is what the engine draws text with no size at all.
    if (text != null) visit(text, 14);
  }
  expect(off, isEmpty, reason: 'text off the type scale');
}
