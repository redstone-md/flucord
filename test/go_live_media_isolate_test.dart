import 'package:flucord/src/data/discord/go_live_media_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the media isolate answers where frames go, and shuts down', () async {
    final plane = GoLiveMediaIsolate();

    // An address on a machine with the native module, nothing on a host
    // without one; either way the worker came up and answered.
    final sink = await plane.nativeFrameSink;
    expect(sink, anyOf(isNull, isPositive));

    await plane.dispose();
  });
}
