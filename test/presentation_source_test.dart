import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every line under lib/src/presentation that matches [pattern], as
/// `path:line: text`. Comment lines are skipped.
List<String> _presentationLinesMatching(RegExp pattern) {
  final offenders = <String>[];
  final sources = Directory('lib/src/presentation')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
  for (final file in sources) {
    final lines = file.readAsLinesSync();
    for (final (index, line) in lines.indexed) {
      if (line.trimLeft().startsWith('//')) continue;
      if (pattern.hasMatch(line)) {
        offenders.add('${file.path}:${index + 1}: ${line.trim()}');
      }
    }
  }
  return offenders;
}

void main() {
  test('presentation widgets draw icons from the shared set only', () {
    // `Icons.x` names a Material glyph and a bare `Icon(` draws one.
    // `FlucordIcon(FlucordIcons.x)` does not match.
    final offenders = _presentationLinesMatching(
      RegExp(r'(?<![\w$])(Icons\.|Icon\()'),
    );

    expect(
      offenders,
      isEmpty,
      reason:
          'Use FlucordIcon(FlucordIcons.x) from '
          'lib/src/theme/flucord_icons.dart instead of a Material icon:\n'
          '${offenders.join('\n')}',
    );
  });

  test('presentation text is no heavier than Medium (500)', () {
    // Weights come from the type roles. The two heavier styles, badge digits
    // and bold a person wrote, are named in flucord_type.dart.
    final offenders = _presentationLinesMatching(
      RegExp(r'FontWeight\.(w[6-9]00|bold)'),
    );

    expect(
      offenders,
      isEmpty,
      reason:
          'Take the weight from a FlucordTextRole (`.style`, or `.strong` '
          'for 500) in lib/src/theme/flucord_type.dart. Count digits use '
          'FlucordType.badgeDigits:\n'
          '${offenders.join('\n')}',
    );
  });
}
