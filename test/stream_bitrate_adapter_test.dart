import 'package:flucord/src/domain/stream_bitrate_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('heavy loss backs the bitrate off in proportion', () {
    final adapter = StreamBitrateAdapter(target: 2000000);

    expect(adapter.report(0.2), 1800000);
    expect(adapter.report(0.5), 1350000);
    expect(adapter.isAdapted, isTrue);
  });

  test('light loss holds, a clean path recovers up to the target', () {
    final adapter = StreamBitrateAdapter(target: 2000000)..report(0.2);

    expect(adapter.report(0.05), isNull);
    expect(adapter.report(0.0), 1944000);
    expect(adapter.report(0.0), 2000000);
    expect(adapter.report(0.0), isNull);
    expect(adapter.isAdapted, isFalse);
  });

  test('the floor holds a picture through any loss', () {
    final adapter = StreamBitrateAdapter(target: 1000000);
    for (var i = 0; i < 20; i++) {
      adapter.report(0.9);
    }
    expect(adapter.bitrate, 200000);
  });
}
