import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

/// How severe a record is. The letters end up in every log line.
enum AppLogLevel {
  info('I', 800),
  warning('W', 900),
  error('E', 1000);

  const AppLogLevel(this.letter, this.developerLevel);

  final String letter;

  /// The dart:developer severity, so DevTools keeps its levels.
  final int developerLevel;
}

/// The app's diagnostic log: one call, three mirrors.
///
/// Every record goes to the log file, the console, and dart:developer (what
/// DevTools shows). The file survives restarts, so a feature that failed in
/// a built app leaves a trace to read afterwards. [open] starts the file;
/// before that, and in tests, records reach the console and DevTools only.
///
/// The log never throws: a broken sink loses lines, it does not take the
/// app down with it.
final class AppLog {
  AppLog._(this._directory, this.maxFileBytes);

  static AppLog? _active;

  /// Where records land once [open] has run. Null while file logging is
  /// off (tests, or a directory that could not be written).
  static String? get path => _active?._file?.path;

  /// A file larger than this rolls over to `flucord.log.1` on the next
  /// record. One previous file is kept.
  final int maxFileBytes;

  final Directory _directory;
  File? _file;
  RandomAccessFile? _handle;
  int _bytes = 0;

  /// Opens the rotating log file inside [directory].
  ///
  /// A file left oversized by the previous run rolls over right away.
  static Future<AppLog> open(
    Directory directory, {
    int maxFileBytes = twoMegabytes,
  }) async {
    final existing = _active;
    if (existing != null) return existing;

    final log = AppLog._(directory, maxFileBytes);
    _active = log;
    await log._start();
    return log;
  }

  static const twoMegabytes = 2 * 1024 * 1024;

  /// An informational record: a state change worth seeing in a timeline.
  static void info(String scope, String message) =>
      _write(AppLogLevel.info, scope, message, null, null);

  /// Something failed but was handled: reconnects, dropped toasts, retries.
  static void warning(String scope, String message, {Object? error}) =>
      _write(AppLogLevel.warning, scope, message, error, null);

  /// Something failed and the operation is dead. Carries the stack.
  static void error(
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => _write(AppLogLevel.error, scope, message, error, stackTrace);

  static void _write(
    AppLogLevel level,
    String scope,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    final line = _formatRecord(DateTime.now(), level, scope, message, error);
    // Straight to stdout, not debugPrint: debugPrint throttles, and under a
    // burst of transport diagnostics the throttled-away lines were exactly
    // the ones that mattered.
    _writeToConsole(line);
    developer.log(
      message,
      name: 'flucord.$scope',
      level: level.developerLevel,
      error: error,
      stackTrace: stackTrace,
    );
    _active?._append(line, stackTrace);
  }

  static Zone? _consoleZone;
  static bool _consoleBroken = false;

  /// Writes to stdout inside its own zone. A Windows GUI app launched
  /// without a console has no valid stdout handle, and the failure arrives
  /// asynchronously where no caller can catch it; the first failure switches
  /// this mirror off. The file keeps recording either way.
  static void _writeToConsole(String line) {
    if (_consoleBroken) return;
    final consoleZone =
        _consoleZone ??
        Zone.current.fork(
          specification: ZoneSpecification(
            handleUncaughtError: (self, parent, zone, error, stackTrace) {
              _consoleBroken = true;
            },
          ),
        );
    _consoleZone = consoleZone;
    try {
      consoleZone.run(() => stdout.writeln(line));
    } on Object {
      _consoleBroken = true;
    }
  }

  static String _formatRecord(
    DateTime time,
    AppLogLevel level,
    String scope,
    String message,
    Object? error,
  ) {
    final buffer = StringBuffer(
      '${_two(time.year)}-${_two(time.month)}-${_two(time.day)} '
      '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}.'
      '${_three(time.millisecond)} [${level.letter}] $scope $message',
    );
    if (error != null) buffer.write(' :: $error');
    return buffer.toString();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
  static String _three(int value) => value.toString().padLeft(3, '0');

  Future<void> _start() async {
    _runSafely(() {
      _directory.createSync(recursive: true);
      final file = File(
        '${_directory.path}${Platform.pathSeparator}flucord.log',
      );
      if (file.existsSync() && file.lengthSync() > maxFileBytes) {
        _rollOver(file: file);
      }
      _file = file;
      _bytes = file.existsSync() ? file.lengthSync() : 0;
      _handle = file.openSync(mode: FileMode.append);
    });
  }

  void _append(String line, StackTrace? stackTrace) {
    _runSafely(() {
      final handle = _handle;
      if (handle == null) return;
      handle.writeStringSync('$line\n');
      _bytes += line.length + 1;
      if (stackTrace != null) {
        handle.writeStringSync('$stackTrace\n');
        _bytes += '$stackTrace'.length + 1;
      }
      if (_bytes > maxFileBytes) {
        handle.flushSync();
        handle.closeSync();
        _rollOver(file: _file!);
        _handle = _file!.openSync(mode: FileMode.append);
        _bytes = 0;
      }
    });
  }

  void _rollOver({required File file}) {
    final previous = File('${file.path}.1');
    if (previous.existsSync()) previous.deleteSync();
    if (file.existsSync()) file.renameSync(previous.path);
  }

  /// Closes the file handle. The app exits fine without this; it exists for
  /// orderly shutdowns and tests.
  void close() {
    _runSafely(() {
      _handle?.closeSync();
    });
    _handle = null;
    _file = null;
    if (_active == this) _active = null;
  }

  /// A file sink that throws is a sink that gets disabled, not one that
  /// takes the caller down.
  static void _runSafely(void Function() action) {
    try {
      action();
    } on Object catch (error) {
      if (_active != null && _active!._handle != null) {
        // The file sink is broken; stop trying to use it.
        _active!._handle = null;
        _active!._file = null;
      }
      _writeToConsole('Flucord log file sink failed: $error');
    }
  }
}
