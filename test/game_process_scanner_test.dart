import 'package:flucord/src/platform/game_process_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the scanner interface', () {
    test('the unavailable scanner sees nothing', () {
      const scanner = UnavailableGameProcessScanner();

      expect(scanner.isSupported, isFalse);
      expect(scanner.runningExecutableBasenames(), isEmpty);
    });
  });

  group('the windows scanner', () {
    test('reports itself unavailable when the libraries are absent', () {
      const scanner = WindowsGameProcessScanner.withLibraries(
        kernel32: null,
        psapi: null,
      );

      expect(scanner.isSupported, isFalse);
      expect(scanner.runningExecutableBasenames(), isEmpty);
    });
  });

  group('executable names', () {
    test(
      'the file name of a windows path is everything after the last separator',
      () {
        expect(executableBasename(r'C:\Games\DRG\FSD.exe'), 'FSD.exe');
        expect(executableBasename('Games/DRG/FSD.exe'), 'FSD.exe');
        expect(executableBasename('FSD.exe'), 'FSD.exe');
        expect(executableBasename(r'C:\Games\FSD.exe'), 'FSD.exe');
        expect(executableBasename('a\\b'), 'b');
        expect(executableBasename('a/b'), 'b');
        expect(executableBasename(''), '');
      },
    );
  });
}
