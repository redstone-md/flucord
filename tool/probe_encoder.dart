// Drives the native encoder against this machine's real display, which is the
// only way to know whether it encodes anything at all.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:flucord/src/data/discord/discord_h264_depacketizer.dart';
import 'package:flucord/src/data/discord/discord_h264_packetizer.dart';
import 'package:flucord/src/data/discord/discord_video_rtp_sender.dart';
import 'package:flucord/src/data/discord/discord_video_stream_transport.dart';
import 'package:flucord/src/data/discord/discord_voice_transport_cipher.dart';
import 'package:flucord/src/data/video/native_video_bindings.dart';
import 'package:flucord/src/data/video/native_video_decoder_service.dart';
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
  // The transport as the stream connection would hold it, encrypting each
  // packet the way the voice socket does before it goes out.
  final cipher = DiscordVoiceTransportCipher(
    mode: DiscordVoiceTransportMode.aes256GcmRtpSize,
    secretKey: List<int>.generate(32, (index) => index),
  );
  var encryptedPackets = 0;
  var encryptedBytes = 0;
  final transport = DiscordVideoStreamTransport(
    ssrc: 0x1234,
    sink: (frame) {
      final packet = cipher.encryptFrame(frame);
      encryptedPackets++;
      encryptedBytes += packet.length;
      return packet.length;
    },
  );
  // The receiving half, so the sender can be checked against itself: what
  // comes back out must be what the encoder put in.
  final depacketizer = DiscordH264Depacketizer();
  // The viewer's half, in-process: what the sender put on the wire is decoded
  // back into pictures exactly as a watching client would.
  final viewer = NativeVideoDecoderService(
    bindings: NativeVideoBindings(DynamicLibrary.open(dll)),
  );
  await viewer.start();
  var pictures = 0;
  var completePictures = 0;
  var pictureWidth = 0;
  var pictureHeight = 0;
  var nonBlackPictures = 0;
  final viewing = viewer.frames.listen((picture) {
    pictures++;
    if (picture.isComplete) completePictures++;
    pictureWidth = picture.width;
    pictureHeight = picture.height;
    // A decoder that produced nothing but black would satisfy every count
    // above while showing a viewer an empty rectangle.
    for (var index = 0; index < picture.pixels.length; index += 4096) {
      if (picture.pixels[index] > 8) {
        nonBlackPictures++;
        break;
      }
    }
  });
  final rebuilt = <int>[];
  var rebuiltUnits = 0;
  var identical = 0;
  var differing = 0;
  final subscription = service.frames.listen((frame) {
    frames++;
    bytes += frame.bytes.length;
    if (frame.isKeyframe) keyframes++;
    // The packetiser runs against every real frame, not a fixture: a payload
    // over the budget or a picture with no marker would never draw.
    for (final unit in DiscordH264Packetizer.splitAnnexB(frame.bytes)) {
      if (DiscordH264Packetizer.isParameterSet(unit)) parameterSets++;
    }
    transport.send(frame);
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
    for (final packet in produced) {
      final unit = depacketizer.accept(packet.payload, marker: packet.marker);
      if (unit == null) continue;
      rebuiltUnits++;
      rebuilt.addAll(unit);
      unawaited(viewer.submit(unit, timestamp: frame.timestamp));
      // Start-code lengths cannot survive the round trip — RTP does not carry
      // them, so the depacketiser chooses its own — but every NAL unit must
      // come back byte for byte. That is what a decoder actually reads.
      final sent = DiscordH264Packetizer.splitAnnexB(frame.bytes);
      final back = DiscordH264Packetizer.splitAnnexB(unit);
      var same = sent.length == back.length;
      for (var index = 0; same && index < sent.length; index++) {
        if (sent[index].length != back[index].length) {
          same = false;
          break;
        }
        for (var byte = 0; byte < sent[index].length; byte++) {
          if (sent[index][byte] != back[index][byte]) {
            same = false;
            break;
          }
        }
      }
      same ? identical++ : differing++;
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
  stdout.writeln(
    'rebuilt access units: $rebuiltUnits, NAL-identical: $identical, '
    'differing: $differing',
  );

  // The last question a machine can answer alone: does a decoder accept what
  // came back off the wire? This is the same Media Foundation H.264 decoder a
  // Discord client on Windows draws with.
  final bindings = NativeVideoBindings(DynamicLibrary.open(dll));
  final stream = Uint8List.fromList(rebuilt);
  final buffer = calloc<Uint8>(stream.length);
  buffer.asTypedList(stream.length).setAll(0, stream);
  final decoded = bindings.decodeProbe(buffer, stream.length);
  calloc.free(buffer);
  stdout.writeln('decoded pictures: $decoded');
  await viewing.cancel();
  await viewer.close();
  stdout.writeln(
    'viewer pictures: $pictures, complete: $completePictures, '
    'non-black: $nonBlackPictures, size: ${pictureWidth}x$pictureHeight',
  );
  stdout.writeln(
    'encrypted packets: $encryptedPackets, bytes on the wire: '
    '$encryptedBytes, transport error: ${transport.error}',
  );

  exit(
    frames > 0 &&
            packets > 0 &&
            oversized == 0 &&
            differing == 0 &&
            decoded > 0 &&
            completePictures > 0 &&
            nonBlackPictures > 0
        ? 0
        : 2,
  );
}
