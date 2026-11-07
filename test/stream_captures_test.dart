import 'dart:typed_data';

import 'package:flucord/src/domain/stream_captures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a window source id names its handle, and nothing else does', () {
    expect(WindowCapture.handleFor('window:42:0'), 42);
    expect(WindowCapture.handleFor('screen:1:0'), isNull);
    expect(WindowCapture.handleFor('window:nope:0'), isNull);
    expect(WindowCapture.handleFor(null), isNull);
  });

  test('a thumbnail averages the area each element covers, as a top-down '
      'bitmap', () {
    // Four by two, with one row of padding: white on the left, black on the
    // right, alpha left at zero the way GDI leaves it.
    const white = [0xff, 0xff, 0xff, 0x00];
    const black = [0x00, 0x00, 0x00, 0x00];
    const pad = [9, 9, 9, 9];
    final row = [...white, ...white, ...black, ...black, ...pad];
    final thumbnail = CaptureThumbnail.fromBgra(
      Uint8List.fromList([...row, ...row]),
      width: 4,
      height: 2,
      stride: 20,
      maxWidth: 2,
      maxHeight: 2,
    );

    expect((thumbnail.width, thumbnail.height), (2, 1));
    final header = ByteData.sublistView(thumbnail.bytes);
    expect(String.fromCharCodes(thumbnail.bytes.take(2)), 'BM');
    expect(header.getInt32(18, Endian.little), 2);
    expect(header.getInt32(22, Endian.little), -1);
    expect(header.getUint16(28, Endian.little), 32);
    expect(thumbnail.bytes.sublist(54), [
      0xff, 0xff, 0xff, 0xff, //
      0x00, 0x00, 0x00, 0xff,
    ]);
  });

  test('a thumbnail never grows a picture smaller than its box', () {
    final thumbnail = CaptureThumbnail.fromBgra(
      Uint8List(4 * 3 * 2),
      width: 3,
      height: 2,
      stride: 12,
    );

    expect((thumbnail.width, thumbnail.height), (3, 2));
  });
}
