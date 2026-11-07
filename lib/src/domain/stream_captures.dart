import 'dart:math' as math;
import 'dart:typed_data';

/// Something Go Live can share: a whole screen or one window.
///
/// Each travels as a source id in the shape a capture source list uses,
/// `screen:<index>:0` or `window:<handle>:0`. This client never varies the
/// tail, but the shape is not ours to change.
sealed class StreamCapture {
  const StreamCapture();

  String get sourceId;

  /// What the picker labels it with.
  String get name;
}

/// A display this machine can share.
///
/// Named by the encoder rather than by a capture library: enumerating sources
/// through WebRTC opens duplications of its own to build thumbnails with, and
/// one of those left open is what refuses the share afterwards.
final class DisplayCapture extends StreamCapture {
  const DisplayCapture({required this.index, required this.name});

  final int index;

  @override
  final String name;

  @override
  String get sourceId => 'screen:$index:0';

  /// Which display a source id names, or the primary when it names none.
  ///
  /// A name this client does not make is the primary display: the capture
  /// takes it by default, and refusing a share over a shape nobody here
  /// writes would be inventing a failure.
  static int displayIndexFor(String? sourceId) {
    if (sourceId == null || !sourceId.startsWith('screen:')) return 0;
    final index = int.tryParse(sourceId.split(':').elementAtOrNull(1) ?? '');
    if (index == null || index < 0) return 0;
    return index;
  }
}

/// One top-level window this machine can share, by its handle.
final class WindowCapture extends StreamCapture {
  const WindowCapture({required this.handle, required this.name});

  /// The platform's handle for it (an `HWND` on Windows).
  final int handle;

  /// The window's title.
  @override
  final String name;

  @override
  String get sourceId => 'window:$handle:0';

  /// The handle a `window:` source id names, or null for any other id.
  static int? handleFor(String? sourceId) {
    if (sourceId == null || !sourceId.startsWith('window:')) return null;
    final handle = int.tryParse(sourceId.split(':').elementAtOrNull(1) ?? '');
    return handle == null || handle == 0 ? null : handle;
  }
}

/// A small picture of a source for the picker, as encoded image bytes.
final class CaptureThumbnail {
  const CaptureThumbnail({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// [bgra] shrunk to fit in [maxWidth] by [maxHeight], keeping its shape,
  /// and stored as an uncompressed bitmap that any image widget can draw.
  ///
  /// Each picture element is the average of the area it covers, so text
  /// stays a grey smear rather than turning into noise. The alpha is made
  /// opaque: a window drawn by GDI leaves it at zero.
  factory CaptureThumbnail.fromBgra(
    Uint8List bgra, {
    required int width,
    required int height,
    required int stride,
    int maxWidth = 320,
    int maxHeight = 180,
  }) {
    final scale = math.min(1.0, math.min(maxWidth / width, maxHeight / height));
    final outWidth = math.max(1, (width * scale).round());
    final outHeight = math.max(1, (height * scale).round());
    final pixels = Uint8List(outWidth * outHeight * 4);
    for (var y = 0; y < outHeight; y++) {
      final top = y * height ~/ outHeight;
      final bottom = math.max(top + 1, (y + 1) * height ~/ outHeight);
      for (var x = 0; x < outWidth; x++) {
        final left = x * width ~/ outWidth;
        final right = math.max(left + 1, (x + 1) * width ~/ outWidth);
        var blue = 0, green = 0, red = 0;
        for (var row = top; row < bottom; row++) {
          var at = row * stride + left * 4;
          for (var column = left; column < right; column++, at += 4) {
            blue += bgra[at];
            green += bgra[at + 1];
            red += bgra[at + 2];
          }
        }
        final count = (bottom - top) * (right - left);
        final out = (y * outWidth + x) * 4;
        pixels[out] = blue ~/ count;
        pixels[out + 1] = green ~/ count;
        pixels[out + 2] = red ~/ count;
        pixels[out + 3] = 0xff;
      }
    }
    return CaptureThumbnail(
      bytes: _bitmap(pixels, outWidth, outHeight),
      width: outWidth,
      height: outHeight,
    );
  }

  final Uint8List bytes;
  final int width;
  final int height;

  /// A 32-bit top-down BMP around packed BGRA rows.
  static Uint8List _bitmap(Uint8List bgra, int width, int height) {
    const headerSize = 14 + 40;
    final file = ByteData(headerSize + bgra.length)
      ..setUint8(0, 0x42) // 'B'
      ..setUint8(1, 0x4d) // 'M'
      ..setUint32(2, headerSize + bgra.length, Endian.little)
      ..setUint32(10, headerSize, Endian.little)
      ..setUint32(14, 40, Endian.little)
      ..setInt32(18, width, Endian.little)
      // Negative: the rows run from the top, as they were captured.
      ..setInt32(22, -height, Endian.little)
      ..setUint16(26, 1, Endian.little)
      ..setUint16(28, 32, Endian.little)
      ..setUint32(34, bgra.length, Endian.little);
    final bytes = file.buffer.asUint8List();
    bytes.setRange(headerSize, bytes.length, bgra);
    return bytes;
  }
}

/// Where the Go Live picker finds windows to share, and the thumbnails it
/// shows for every source. The screens themselves come from the encoder.
abstract interface class CaptureCatalog {
  /// The windows that can be shared now, front first.
  List<WindowCapture> windows();

  /// A thumbnail for each of [sources] that could be captured, by source id.
  ///
  /// Every display capture taken for these is closed before this completes,
  /// so a share started after it does not find its display held.
  Future<Map<String, CaptureThumbnail>> thumbnails(List<StreamCapture> sources);
}

/// A platform with no windows to list and no thumbnails to take.
final class UnavailableCaptureCatalog implements CaptureCatalog {
  const UnavailableCaptureCatalog();

  @override
  List<WindowCapture> windows() => const [];

  @override
  Future<Map<String, CaptureThumbnail>> thumbnails(
    List<StreamCapture> sources,
  ) async => const {};
}
