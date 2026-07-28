import 'dart:typed_data';

import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settings', () {
    test('rejects anything the encoder could not act on', () {
      expect(const VideoEncoderSettings().isValid, isTrue);
      expect(const VideoEncoderSettings(width: 0).isValid, isFalse);
      expect(const VideoEncoderSettings(height: -1).isValid, isFalse);
      expect(const VideoEncoderSettings(framesPerSecond: 0).isValid, isFalse);
      expect(const VideoEncoderSettings(bitrate: 0).isValid, isFalse);
      expect(const VideoEncoderSettings(displayIndex: -1).isValid, isFalse);
    });

    test('defaults to what Discord sends for a 720p share', () {
      const settings = VideoEncoderSettings();

      expect(settings.width, 1280);
      expect(settings.height, 720);
      expect(settings.framesPerSecond, 30);
      expect(settings.bitrate, 2500000);
      expect(settings.displayIndex, 0);
    });
  });

  group('failures', () {
    test('every one carries a message the room can show', () {
      for (final failure in VideoEncoderFailure.values) {
        final exception = VideoEncoderException(failure);
        expect(exception.message, isNotEmpty);
        expect(exception.toString(), exception.message);
      }
    });
  });

  group('frame', () {
    test('carries what the sender needs to packetise it', () {
      final frame = EncodedVideoFrame(
        bytes: Uint8List.fromList(const [0, 0, 0, 1, 0x67]),
        timestamp: const Duration(milliseconds: 33),
        isKeyframe: true,
      );

      // An Annex B start code, which is what the RTP packetiser splits on.
      expect(frame.bytes.take(4), [0, 0, 0, 1]);
      expect(frame.timestamp.inMilliseconds, 33);
      expect(frame.isKeyframe, isTrue);
    });
  });
}
