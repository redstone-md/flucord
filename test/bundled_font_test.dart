import 'dart:convert';

import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app font ships in the bundle and draws its own faces', (
    tester,
  ) async {
    final family = FlucordTheme.dark.textTheme.bodyMedium!.fontFamily!;
    // The engine reads this manifest to find fonts on Windows, macOS and
    // Linux alike. A family missing from it falls back to whatever the
    // system has, which is how Bahnschrift only ever existed on Windows.
    final manifest = (jsonDecode(
      await tester.runAsync(() => rootBundle.loadString('FontManifest.json')) ??
          '[]',
    ) as List).cast<Map<String, Object?>>();
    final entry = manifest.where((font) => font['family'] == family);
    expect(entry, isNotEmpty, reason: '$family is not in the app bundle');

    final loader = FontLoader(family);
    for (final font in (entry.single['fonts']! as List).cast<Map>()) {
      loader.addFont(rootBundle.load(font['asset']! as String));
    }
    await tester.runAsync(loader.load);

    double widthOf(FontWeight weight) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'iiii',
          style: TextStyle(fontFamily: family, fontSize: 20, fontWeight: weight),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(painter.dispose);
      return painter.width;
    }

    // The test font draws every letter one em wide, so 80 here. A real face
    // draws a narrow `i`, and its bold face draws it wider than its regular.
    expect(widthOf(FontWeight.w400), lessThan(40));
    expect(widthOf(FontWeight.w700), greaterThan(widthOf(FontWeight.w400)));
  });
}
