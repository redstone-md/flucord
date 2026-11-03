import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_font.dart';

void main() {
  test('the app is set in Golos Text', () {
    expect(FlucordType.family, 'Golos Text');
  });

  testWidgets('the app font ships in the bundle and draws its own faces', (
    tester,
  ) async {
    // A family missing from the bundle falls back to whatever the system has,
    // which is how Bahnschrift only ever existed on Windows.
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
    // draws a narrow `i`, and each heavier face draws it wider. Regular,
    // Medium and SemiBold are separate files, so each weight gets its own.
    final regular = widthOf(FontWeight.w400);
    final medium = widthOf(FontWeight.w500);
    final semiBold = widthOf(FontWeight.w600);
    expect(regular, lessThan(40));
    expect(medium, greaterThan(regular));
    expect(semiBold, greaterThan(medium));
  });

  testWidgets('the font licence ships beside the font', (tester) async {
    // The SIL OFL asks that the licence travel with the font.
    final licence = await tester.runAsync(
      () => rootBundle.loadString('assets/fonts/golos_text/OFL.txt'),
    );

    expect(licence, contains('SIL Open Font License, Version 1.1'));
    expect(licence, contains('Golos Text Project Authors'));
  });
}
