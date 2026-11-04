import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The working-tree half of the snowflake rule in
/// tool/audit_public_repository.ps1. The audit reads the whole history, but
/// only in CI; this test catches a realistic id while it is still a local
/// edit, before history keeps it forever. The patterns match the audit's.
final _snowflake = RegExp(r'(?<![0-9A-Fa-f])[0-9]{17,20}(?![0-9A-Fa-f])');
final _fixtureShape = RegExp(r'^[1-9]0{9,}[0-9]{0,8}$');

Set<String> _allowedSnowflakes() => File('tool/allowed_snowflakes.txt')
    .readAsLinesSync()
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty && !line.startsWith('#'))
    .toSet();

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

    final allowed = _allowedSnowflakes();
    final offenders = <String>[];
    for (final match in (grep.stdout as String).split('\n')) {
      final separator = match.indexOf(':', match.indexOf(':') + 1);
      if (separator < 0) continue;
      for (final id in _snowflake.allMatches(match.substring(separator + 1))) {
        final value = id[0]!;
        if (!allowed.contains(value) && !_fixtureShape.hasMatch(value)) {
          offenders.add('${match.substring(0, separator)}: $value');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use a fixture-shaped id (one non-zero digit, at least nine zeroes, '
          'a short count: 100000000000000221). A value that is already in '
          'history and names no one goes in tool/allowed_snowflakes.txt with '
          'a comment:\n${offenders.join('\n')}',
    );
  });
}
