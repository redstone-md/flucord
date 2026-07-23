import 'dart:ffi';

final class NativeDaveBuffers {
  const NativeDaveBuffers._();

  static Pointer<Uint8> allocate(Allocator allocator, List<int> bytes) {
    if (bytes.isEmpty) return nullptr;
    for (final byte in bytes) {
      if (byte < 0 || byte > 0xff) {
        throw RangeError.range(byte, 0, 0xff, 'byte');
      }
    }
    final pointer = allocator<Uint8>(bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  static List<int> copy(Pointer<Uint8> pointer, int length) {
    if (pointer == nullptr || length == 0) return const [];
    return List<int>.unmodifiable(pointer.asTypedList(length));
  }
}
