// Drives the native encoder against this machine's real display, which is the
// only way to know whether it encodes anything at all.
import 'dart:ffi';
import 'dart:io';

import 'package:flucord/src/data/discord/discord_h264_packetizer.dart';
import 'package:flucord/src/data/discord/discord_video_rtp_sender.dart';
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
  var packets = 0;
  var fragments = 0;
  var oversized = 0;
  var parameterSets = 0;
  final sender = DiscordVideoRtpSender(ssrc: 0x1234);
  final subscription = service.frames.listen((frame) {
    frames++;
    bytes += frame.bytes.length;
    if (frame.isKeyframe) keyframes++;
    // The packetiser runs against every real frame, not a fixture: a payload
    // over the budget or a picture with no marker would never draw.
    for (final unit in DiscordH264Packetizer.splitAnnexB(frame.bytes)) {
      if (DiscordH264Packetizer.isParameterSet(unit)) parameterSets++;
    }
    final produced = sender.packetsFor(frame);
    packets += produced.length;
    for (final packet in produced) {
      if (packet.payload.length > DiscordH264Packetizer.maxPayloadSize) {
        oversized++;
      }
      if ((packet.payload[0] & 0x1f) == 28) fragments++;
    }
    if (produced.isNotEmpty && !produced.last.marker) {
      stdout.writeln('BAD: picture with no marker');
    }
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
  stdout.writeln(
    'rtp packets: $packets, fragments: $fragments, oversized: $oversized, '
    'parameter sets: $parameterSets, final sequence: ${sender.sequence}',
  );
  exit(frames > 0 && packets > 0 && oversized == 0 ? 0 : 2);
}
