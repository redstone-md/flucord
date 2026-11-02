// Compiles the domain benchmark to native code and runs it. The table goes to
// stdout and the compiler's messages go to stderr, so a redirect holds only the
// table. README.md says how to run it.
import 'dart:io';

Future<void> main() async {
  final binary = 'build/domain_bench${Platform.isWindows ? '.exe' : ''}';
  await Directory.fromUri(Platform.script.resolve('build/')).create();

  // Dart resolves the package of the working folder, so it has to be this one.
  // From the repo root, it would try to resolve the whole app.
  final compile = await Process.run(
    Platform.resolvedExecutable,
    ['compile', 'exe', 'domain_bench.dart', '-o', binary],
    workingDirectory: Platform.script.resolve('.').toFilePath(),
  );
  stderr
    ..write(compile.stdout)
    ..write(compile.stderr);
  if (compile.exitCode != 0) {
    exitCode = compile.exitCode;
    return;
  }

  final run = await Process.start(
    Platform.script.resolve(binary).toFilePath(),
    const [],
    mode: ProcessStartMode.inheritStdio,
  );
  exitCode = await run.exitCode;
}
