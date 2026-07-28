// Drives the native encoder against this machine's real display, which is the
// only way to know whether it encodes anything at all.
import 'dart:ffi';
import 'dart:io';

import 'package:flucord/src/data/video/native_video_bindings.dart';
import 'package:flucord/src/data/video/native_video_encoder_service.dart';
import 'package:flucord/src/domain/video_encoder.dart';

Future<void> main() async {
  final dll =
      Directory.current.path +
      r'\build\windows\x64\runner\Release\flucord_video.dll';
  final service = NativeVideoEncoderService(
    bindings: NativeVideoBindings(DynamicLibrary.open(dll)),
  );

  stdout.writeln('supported: ${service.isSupported}');
  stdout.writeln('displays: ${service.displayCount}');

  var frames = 0;
  var keyframes = 0;
  var bytes = 0;
  final subscription = service.frames.listen((frame) {
    frames++;
    bytes += frame.bytes.length;
    if (frame.isKeyframe) keyframes++;
    if (frames <= 3) {
      final head = frame.bytes.take(5).toList();
      stdout.writeln(
        'frame $frames: ${frame.bytes.length} bytes, key=${frame.isKeyframe}, '
        'ts=${frame.timestamp.inMilliseconds}ms, head=$head',
      );
    }
  });

  try {
    await service.start(
      const VideoEncoderSettings(
        width: 1280,
        height: 720,
        framesPerSecond: 15,
        bitrate: 1500000,
      ),
    );
    stdout.writeln('started');
  } on VideoEncoderException catch (error) {
    stdout.writeln('start refused: ${error.failure} — ${error.message}');
    exit(1);
  }

  await Future<void>.delayed(const Duration(seconds: 3));
  await service.requestKeyframe();
  await Future<void>.delayed(const Duration(seconds: 2));
  await service.stop();
  await subscription.cancel();

  stdout.writeln('frames: $frames, keyframes: $keyframes, bytes: $bytes');
  exit(frames > 0 ? 0 : 2);
}
