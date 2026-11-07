/// The text rules every committed line keeps. `tool/check_staged.dart` (the
/// pre-commit hook) applies them to the lines a commit adds, and
/// `test/repository_snowflake_test.dart` applies the id rule to the working
/// tree.
///
/// The id rule is the local half of the one in
/// `tool/audit_public_repository.ps1`, and its patterns match the audit's.
/// The audit reads the whole history, so an id has to be stopped before it is
/// committed.
library;

import 'dart:io';

final _snowflake = RegExp(r'(?<![0-9A-Fa-f])[0-9]{17,20}(?![0-9A-Fa-f])');

/// The shape test fixtures number their ids in: one digit that is not zero,
/// at least nine zeroes, then a short count, as in 100000000000000221. The
/// audit explains why a real id of this shape is very unlikely.
final _fixtureShape = RegExp(r'^[1-9]0{9,}[0-9]{0,8}$');

const _emDash = '\u2014';

/// How to fix a realistic id, for the messages that report one.
const snowflakeAdvice =
    'Use a fixture-shaped id (one non-zero digit, at least nine zeroes, a '
    'short count: 100000000000000221). A value that is already in history and '
    'names no one goes in tool/allowed_snowflakes.txt with a comment.';

/// The ids `tool/allowed_snowflakes.txt` lets through.
Set<String> readAllowedSnowflakes() => File('tool/allowed_snowflakes.txt')
    .readAsLinesSync()
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty && !line.startsWith('#'))
    .toSet();

/// The ids in [text] that could be real Discord ids.
Iterable<String> realisticSnowflakes(String text, Set<String> allowed) =>
    _snowflake
        .allMatches(text)
        .map((match) => match[0]!)
        .where((id) => !allowed.contains(id) && !_fixtureShape.hasMatch(id));

/// Every rule the added lines of [diff] break, one `path:line: problem` per
/// finding. [diff] is `git diff -U0` output, so each `+` line is an added line
/// and each hunk header names where the added lines start.
List<String> addedLineProblems(String diff, Set<String> allowed) {
  final problems = <String>[];
  var path = '';
  var line = 0;
  // An added line can itself start with `++ `, so `+++` names a file only
  // in the header before a file's first hunk.
  var inHeader = false;
  for (final row in diff.split('\n')) {
    if (row.startsWith('diff --git ')) {
      inHeader = true;
    } else if (inHeader && row.startsWith('+++ ')) {
      path = row.startsWith('+++ b/') ? row.substring(6) : row.substring(4);
    } else if (row.startsWith('@@')) {
      inHeader = false;
      line = int.parse(RegExp(r'\+(\d+)').firstMatch(row)![1]!);
    } else if (!inHeader && row.startsWith('+')) {
      final text = row.substring(1);
      for (final id in realisticSnowflakes(text, allowed)) {
        problems.add('$path:$line: realistic Discord id $id');
      }
      if (text.contains(_emDash)) problems.add('$path:$line: em dash');
      line++;
    }
  }
  return problems;
}
