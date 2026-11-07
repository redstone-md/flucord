import 'package:flucord/src/data/video/native_video_bindings.dart';
import 'package:flucord/src/data/video/native_video_encoder_service.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a capture that ended on a closed window says only that', () {
    final ended = nativeCaptureEnded(
      platformCode: 0,
      platformStage: NativeVideoStage.windowClosed,
    );

    expect(ended.failure, VideoEncoderFailure.windowClosed);
    expect('$ended', 'The shared window was closed.');
  });

  test('any other end is a lost capture, with the step that refused', () {
    final ended = nativeCaptureEnded(
      platformCode: 0x887a0026,
      platformStage: NativeVideoStage.duplicate,
    );

    expect(ended.failure, VideoEncoderFailure.captureLost);
    expect('$ended', endsWith('(0x887a0026 at step 3)'));
  });
}
