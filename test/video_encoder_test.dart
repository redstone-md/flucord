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

    test('carries what the platform said, when it said anything', () {
      // "No display" covers a machine with no output at all, an index that
      // has gone, and a duplication another process is holding. Only the
      // HRESULT separates them, and without it a report says nothing usable.
      const refused = VideoEncoderException(
        VideoEncoderFailure.noDisplay,
        platformCode: -2005270490,
      );

      expect(refused.toString(), contains('0x887a0026'));

      const quiet = VideoEncoderException(
        VideoEncoderFailure.noDisplay,
        platformCode: 0,
      );

      expect(quiet.toString(), quiet.message);
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
