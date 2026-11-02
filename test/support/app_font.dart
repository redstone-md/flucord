import 'dart:convert';

import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the app's bundled font, so text in this test is measured with the
/// real faces rather than the test font, which draws every letter 1 em wide.
///
/// It reads the font manifest, which the engine also reads on Windows, macOS
/// and Linux, so it fails when the font is not in the app bundle.
Future<void> loadAppFont(WidgetTester tester) async {
  final manifest = await tester.runAsync(
    () => rootBundle.loadString('FontManifest.json'),
  );
  final fonts = (jsonDecode(manifest ?? '[]') as List)
      .cast<Map<String, Object?>>()
      .where((font) => font['family'] == FlucordType.family);
  expect(fonts, isNotEmpty, reason: '${FlucordType.family} is not bundled');

  final loader = FontLoader(FlucordType.family);
  for (final face in (fonts.single['fonts']! as List).cast<Map>()) {
    loader.addFont(rootBundle.load(face['asset']! as String));
  }
  await tester.runAsync(loader.load);
}
