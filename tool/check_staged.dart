/// Refuses a commit whose added lines break a rule in
/// `tool/repository_text_rules.dart`. `.githooks/pre-commit` runs it.
library;

import 'dart:io';

import 'repository_text_rules.dart';

void main() {
  final diff = Process.runSync('git', [
    'diff',
    '--cached',
    '--no-color',
    '--no-ext-diff',
    '-U0',
    '--diff-filter=ACMR',
  ]);
  if (diff.exitCode != 0) {
    stderr.write(diff.stderr);
    exit(diff.exitCode);
  }

  final problems = addedLineProblems(
    diff.stdout as String,
    readAllowedSnowflakes(),
  );
  if (problems.isEmpty) return;

  stderr
    ..writeln('This commit adds lines that break the repository text rules:')
    ..writeAll(problems.map((problem) => '  $problem\n'))
    ..writeln()
    ..writeln(snowflakeAdvice)
    ..writeln(
      'Replace an em dash with a comma, colon, semicolon, parentheses or a '
      'new sentence.',
    );
  exit(1);
}
