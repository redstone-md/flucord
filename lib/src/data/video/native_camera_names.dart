import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// `flucord_video_camera_name`: writes UTF-8 into the buffer and answers how
/// many bytes it needed, including the terminator.
typedef CameraNameReader =
    int Function(int index, Pointer<Utf8> buffer, int capacity);

/// Turns the native two-call name protocol into a Dart list.
///
/// Split from the service because that half cannot be tested at all — it needs
/// `flucord_video.dll` and a camera — while the buffer sizing, the terminator
/// arithmetic and the fallback naming are exactly the parts that would break
/// quietly and leave a picker full of blanks.
abstract final class NativeCameraNames {
  static List<String> read({
    required int count,
    required CameraNameReader name,
  }) => [for (var index = 0; index < count; index++) at(index, name)];

  /// One camera's name, asking for its length first.
  ///
  /// A camera whose name cannot be read still gets a row: it can be chosen by
  /// position, and dropping it would renumber every camera after it — the
  /// second webcam would silently become the first.
  static String at(int index, CameraNameReader name) {
    // One byte is the terminator alone, which is a name of nothing.
    final needed = name(index, nullptr, 0);
    if (needed <= 1) return fallbackFor(index);
    final buffer = calloc<Uint8>(needed).cast<Utf8>();
    try {
      if (name(index, buffer, needed) <= 0) return fallbackFor(index);
      final text = buffer.toDartString();
      return text.isEmpty ? fallbackFor(index) : text;
    } finally {
      calloc.free(buffer);
    }
  }

  /// What a camera is called when the platform will not say. One-based, since
  /// it is shown to somebody choosing between them.
  static String fallbackFor(int index) => 'Camera ${index + 1}';
}
