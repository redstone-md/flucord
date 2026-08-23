import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/app_log.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('flucord-app-log-');
  });

  tearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // The OS may still hold the file on Windows; the temp dir cleans up.
    }
  });

  File logFile() =>
      File('${directory.path}${Platform.pathSeparator}flucord.log');
  File rolledFile() =>
      File('${directory.path}${Platform.pathSeparator}flucord.log.1');

  test('records before open reach no file but do not throw', () {
    AppLog.info('test', 'nobody opened the log yet');
  });

  test(
    'records land in the file with scope, level, error, and stack',
    () async {
      final log = await AppLog.open(directory);
      addTearDown(log.close);

      AppLog.info('voice', 'connected');
      AppLog.warning('desktop', 'tray unavailable', error: 'no icon');
      AppLog.error(
        'connection',
        'bootstrap failed',
        error: StateError('bad session'),
        stackTrace: StackTrace.fromString('fake stack line'),
      );

      final contents = logFile().readAsStringSync();
      expect(contents, contains('[I] voice connected'));
      expect(contents, contains('[W] desktop tray unavailable :: no icon'));
      expect(
        contents,
        contains('[E] connection bootstrap failed :: Bad state: bad session'),
      );
      expect(contents, contains('fake stack line'));
    },
  );

  test('an oversized file rolls over and keeps one previous file', () async {
    final log = await AppLog.open(directory, maxFileBytes: 120);
    addTearDown(log.close);

    AppLog.info('test', 'first record, long enough to matter');
    AppLog.info('test', 'second record, long enough to matter');
    AppLog.info('test', 'third record, long enough to matter');

    expect(rolledFile().existsSync(), isTrue);
    expect(rolledFile().readAsStringSync(), contains('first record'));
    expect(rolledFile().readAsStringSync(), contains('second record'));
    expect(logFile().readAsStringSync(), contains('third record'));
    expect(logFile().readAsStringSync(), isNot(contains('first record')));
  });

  test(
    'a file left oversized by the previous run rolls over on open',
    () async {
      final first = await AppLog.open(directory);
      AppLog.info('test', 'previous run ${List.filled(200, 'x').join()}');
      first.close();

      final second = await AppLog.open(directory, maxFileBytes: 100);
      addTearDown(second.close);

      expect(rolledFile().existsSync(), isTrue);
      expect(rolledFile().readAsStringSync(), contains('previous run'));
      AppLog.info('test', 'fresh run');
      expect(logFile().readAsStringSync(), contains('fresh run'));
    },
  );

  test('open twice keeps the first file', () async {
    final first = await AppLog.open(directory);
    final second = await AppLog.open(directory);
    addTearDown(first.close);
    expect(second, same(first));
    AppLog.info('test', 'still the first file');
    expect(logFile().readAsStringSync(), contains('still the first file'));
  });
}
