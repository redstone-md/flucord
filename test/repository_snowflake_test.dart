import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/repository_text_rules.dart';

void main() {
  test('tracked and new files carry no realistic Discord ids', () {
    // --untracked: a test file an agent just wrote is not added yet.
    final grep = Process.runSync('git', [
      'grep',
      '-I',
      '-n',
      '-E',
      '--untracked',
      '[0-9]{17,20}',
    ]);
    expect(grep.exitCode, anyOf(0, 1), reason: '${grep.stderr}');

    final allowed = parseAllowedSnowflakes(
      File(allowedSnowflakesPath).readAsStringSync(),
    );
    final offenders = <String>[];
    for (final match in (grep.stdout as String).split('\n')) {
      final separator = match.indexOf(':', match.indexOf(':') + 1);
      if (separator < 0) continue;
      for (final id in realisticSnowflakes(
        match.substring(separator + 1),
        allowed,
      )) {
        offenders.add('${match.substring(0, separator)}: $id');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '$snowflakeAdvice\n${offenders.join('\n')}',
    );
  });

  test('a commit is checked on the lines it adds, where they land', () {
    // Split so this file carries no realistic id of its own.
    const leaked =
        '1139323097930027'
        '999';
    const diff =
        'diff --git a/test/a_test.dart b/test/a_test.dart\n'
        '--- a/test/a_test.dart\n'
        '+++ b/test/a_test.dart\n'
        '@@ -3,0 +4,3 @@\n'
        "+const fixture = '100000000000000221';\n"
        "+const leaked = '$leaked';\n"
        '+++ looks like a header \u2014 but is an added line\n'
        '@@ -20 +23 @@\n'
        "-const removed = '$leaked';\n"
        "+const allowed = '1139323097930027002';\n";

    expect(addedLineProblems(diff, {'1139323097930027002'}), [
      'test/a_test.dart:5: realistic Discord id $leaked',
      'test/a_test.dart:6: em dash',
    ]);
  });
}
