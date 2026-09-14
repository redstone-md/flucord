// Exercises the native display capture without the app around it.
//
// Screen sharing is the one path that cannot be reached from a widget test —
// it fails inside Desktop Duplication, on hardware, and every report so far
// has been a screenshot of a tooltip. This opens the module directly, prints
// what DXGI says the machine has, and tries to capture each display in turn,
// so a failure can be read rather than guessed at.
//
// Run it against a built module:
//   dart run tool/probe_display_capture.dart
//   dart run tool/probe_display_capture.dart path\to\flucord_video.dll
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _CounterNative = Int32 Function();
typedef _Counter = int Function();
typedef _DescribeNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _Describe = int Function(Pointer<Utf8>, int);
typedef _FrameCallback =
    Void Function(Pointer<Void>, Pointer<Uint8>, Int32, Int64, Int32);
typedef _OpenNative =
    Int32 Function(Pointer<_Config>, Pointer<NativeFunction<_FrameCallback>>,
        Pointer<Void>, Pointer<Pointer<Void>>);
typedef _Open =
    int Function(Pointer<_Config>, Pointer<NativeFunction<_FrameCallback>>,
        Pointer<Void>, Pointer<Pointer<Void>>);

/// The module refuses to open without somewhere to hand frames, so the probe
/// supplies a sink that counts them and drops them. A listener rather than a
/// plain function pointer: the encoder calls back from its capture thread,
/// and Dart will not run an isolate-bound callback there.
var _frames = 0;

void _onFrame(
  Pointer<Void> userData,
  Pointer<Uint8> data,
  int length,
  int timestampUs,
  int isKeyframe,
) {
  _frames++;
}

typedef _CloseNative = Void Function(Pointer<Void>);
typedef _Close = void Function(Pointer<Void>);

final class _Config extends Struct {
  @Int32()
  external int displayIndex;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int framesPerSecond;
  @Int32()
  external int bitrate;
}

const _statusNames = {
  0: 'ok',
  1: 'unsupported',
  2: 'no display',
  3: 'encoder',
  4: 'state',
  5: 'no camera',
};

const _stageNames = {
  0: 'none',
  1: 'finding the output',
  2: 'creating a device on its adapter',
  3: 'duplicating onto that device',
  4: 'duplicating onto the original device',
};

Future<void> main(List<String> arguments) async {
  final path = arguments.isNotEmpty
      ? arguments.first
      : r'build\windows\x64\runner\Debug\flucord_video.dll';
  if (!File(path).existsSync()) {
    stderr.writeln('No module at $path — build the Windows app first.');
    exitCode = 2;
    return;
  }
  final library = DynamicLibrary.open(path);
  final displayCount = library
      .lookupFunction<_CounterNative, _Counter>('flucord_video_display_count')();
  stdout.writeln('displays reported: $displayCount');
  stdout.writeln(_describe(library));

  final open = library.lookupFunction<_OpenNative, _Open>('flucord_video_open');
  final close =
      library.lookupFunction<_CloseNative, _Close>('flucord_video_close');
  final lastError = library
      .lookupFunction<_CounterNative, _Counter>('flucord_video_last_error');
  final lastStage = library.lookupFunction<_CounterNative, _Counter>(
    'flucord_video_last_error_stage',
  );

  for (var index = 0; index < (displayCount == 0 ? 1 : displayCount); index++) {
    final config = calloc<_Config>();
    config.ref
      ..displayIndex = index
      ..width = 1280
      ..height = 720
      ..framesPerSecond = 30
      ..bitrate = 2500000;
    final handle = calloc<Pointer<Void>>();
    _frames = 0;
    final sink = NativeCallable<_FrameCallback>.listener(_onFrame);
    final status = open(config, sink.nativeFunction, nullptr, handle);
    final name = _statusNames[status] ?? 'status $status';
    if (status == 0) {
      // A capture that opens and produces nothing is still broken, so the
      // probe waits long enough for a frame or two to arrive.
      // Awaited rather than slept through: the frame callback is a listener,
      // and a blocked isolate never runs it — which had this reporting zero
      // frames from a capture that was working.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      stdout.writeln('display $index: captured, $_frames frames');
      // And again while the first is still open. Discord's own share does
      // exactly this — a picker that grabs thumbnails, then a capture — and
      // if the second one is refused, that is the bug the room reports.
      final second = calloc<Pointer<Void>>();
      final again = open(config, sink.nativeFunction, nullptr, second);
      if (again == 0) {
        stdout.writeln('display $index: a second capture opened too');
        close(second.value);
      } else {
        final code = lastError().toUnsigned(32).toRadixString(16);
        final stage = _stageNames[lastStage()] ?? 'stage ${lastStage()}';
        stdout.writeln(
          'display $index: a second capture was refused — 0x$code while $stage',
        );
      }
      calloc.free(second);
      close(handle.value);
    } else {
      final code = lastError().toUnsigned(32).toRadixString(16);
      final stage = _stageNames[lastStage()] ?? 'stage ${lastStage()}';
      stdout.writeln('display $index: $name — 0x$code while $stage');
    }
    sink.close();
    calloc
      ..free(handle)
      ..free(config);
  }
}

String _describe(DynamicLibrary library) {
  final describe = library.lookupFunction<_DescribeNative, _Describe>(
    'flucord_video_describe_displays',
  );
  final buffer = calloc<Uint8>(4096).cast<Utf8>();
  try {
    final length = describe(buffer, 4096);
    return length <= 0 ? '(nothing reported)' : buffer.toDartString();
  } finally {
    calloc.free(buffer);
  }
}
