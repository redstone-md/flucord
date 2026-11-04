import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presentation widgets draw icons from the shared set only', () {
    // `Icons.x` names a Material glyph and a bare `Icon(` draws one.
    // `FlucordIcon(FlucordIcons.x)` does not match.
    final material = RegExp(r'(?<![\w$])(Icons\.|Icon\()');
    final offenders = <String>[];
    final sources = Directory('lib/src/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in sources) {
      final lines = file.readAsLinesSync();
      for (final (index, line) in lines.indexed) {
        if (line.trimLeft().startsWith('//')) continue;
        if (material.hasMatch(line)) {
          offenders.add('${file.path}:${index + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use FlucordIcon(FlucordIcons.x) from '
          'lib/src/theme/flucord_icons.dart instead of a Material icon:\n'
          '${offenders.join('\n')}',
    );
  });
}
