import 'dart:typed_data';

import 'package:flucord/src/data/video/native_video_decoder_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A module that exists nowhere, so the worker's open answers the way it
/// does on a machine without the native module: the failure has to reach
/// the caller instead of a spinner standing in for it.
const _missingModule = 'flucord_video_missing_module.dll';

void main() {
  test(
    'a decoder whose module will not load is an error, not a silence',
    () async {
      final service = NativeVideoDecoderService(libraryPath: _missingModule);
      addTearDown(service.close);

      expect(service.isSupported, isFalse);
      await expectLater(service.start(), throwsStateError);
    },
  );

  test(
    'a decoder that never opened stops cleanly and hands out no frames',
    () async {
      final service = NativeVideoDecoderService(libraryPath: _missingModule);
      addTearDown(service.close);

      await expectLater(service.start(), throwsStateError);

      var drawn = 0;
      final frames = service.frames.listen((_) => drawn++);
      addTearDown(frames.cancel);
      await service.submit(Uint8List.fromList([1, 2, 3]));
      await service.stop();

      expect(drawn, 0);
    },
  );
}
