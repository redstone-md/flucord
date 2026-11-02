import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_font.dart';

void main() {
  testWidgets('the app font ships in the bundle and draws its own faces', (
    tester,
  ) async {
    // A family missing from the bundle falls back to whatever the system has,
    // which is how Bahnschrift only ever existed on Windows.
    expect(
      FlucordTheme.dark.textTheme.bodyMedium!.fontFamily,
      FlucordType.family,
    );
    await loadAppFont(tester);

    double widthOf(FontWeight weight) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'iiii',
          style: TextStyle(
            fontFamily: FlucordType.family,
            fontSize: 20,
            fontWeight: weight,
          ),
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
