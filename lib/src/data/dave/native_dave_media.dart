import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../domain/voice_dave.dart';
import 'native_dave_bindings.dart';
import 'native_dave_buffers.dart';

final class NativeDaveKeyRatchet implements VoiceDaveKeyRatchet {
  NativeDaveKeyRatchet(this._bindings, this._handle);

  final NativeDaveBindings _bindings;
  DaveKeyRatchetHandle _handle;
  bool _disposed = false;

  DaveKeyRatchetHandle get handle {
    _checkActive();
    return _handle;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bindings.keyRatchetDestroy(_handle);
    _handle = nullptr;
  }

  void _checkActive() {
    if (_disposed) throw StateError('DAVE key ratchet is already disposed');
  }
}

final class NativeDaveEncryptor implements VoiceDaveEncryptor {
  NativeDaveEncryptor.create(this._bindings)
    : _handle = _bindings.encryptorCreate() {
    if (_handle == nullptr) {
      throw StateError('libdave failed to create an encryptor');
    }
  }

  final NativeDaveBindings _bindings;
  DaveEncryptorHandle _handle;
  bool _disposed = false;

  @override
  int get protocolVersion {
    _checkActive();
    return _bindings.encryptorGetProtocolVersion(_handle);
  }

  @override
  bool get hasKeyRatchet {
    _checkActive();
    return _bindings.encryptorHasKeyRatchet(_handle);
  }

  @override
  bool get isPassthrough {
    _checkActive();
    return _bindings.encryptorIsPassthrough(_handle);
  }

  @override
  void setKeyRatchet(VoiceDaveKeyRatchet keyRatchet) {
    _checkActive();
    final native = _nativeRatchet(keyRatchet);
    _bindings.encryptorSetKeyRatchet(_handle, native.handle);
  }

  @override
  void setPassthrough(bool enabled) {
    _checkActive();
    _bindings.encryptorSetPassthrough(_handle, enabled);
  }

  @override
  void assignSsrcToCodec(int ssrc, DaveMediaCodec codec) {
    _checkActive();
    _checkSsrc(ssrc);
    _bindings.encryptorAssignSsrcToCodec(_handle, ssrc, _codecCode(codec));
  }

  @override
  List<int> encrypt({
    required DaveMediaType mediaType,
    required int ssrc,
    required List<int> frame,
  }) {
    _checkActive();
    _checkSsrc(ssrc);
    return using((arena) {
      final input = NativeDaveBuffers.allocate(arena, frame);
      final capacity = _bindings.encryptorGetMaxCiphertextSize(
        _handle,
        _mediaTypeCode(mediaType),
        frame.length,
      );
      final output = capacity == 0 ? nullptr : arena<Uint8>(capacity);
      final written = arena<Size>();
      final result = _bindings.encryptorEncrypt(
        _handle,
        _mediaTypeCode(mediaType),
        ssrc,
        input,
        frame.length,
        output,
        capacity,
        written,
      );
      if (result != 0) {
        throw DaveFrameException(
          _encryptFailure(result),
          operation: 'encryption',
        );
      }
      _checkWrittenSize(written.value, capacity);
      return NativeDaveBuffers.copy(output, written.value);
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bindings.encryptorDestroy(_handle);
    _handle = nullptr;
  }

  void _checkActive() {
    if (_disposed) throw StateError('DAVE encryptor is already disposed');
  }
}

final class NativeDaveDecryptor implements VoiceDaveDecryptor {
  NativeDaveDecryptor.create(this._bindings)
    : _handle = _bindings.decryptorCreate() {
    if (_handle == nullptr) {
      throw StateError('libdave failed to create a decryptor');
    }
  }

  final NativeDaveBindings _bindings;
  DaveDecryptorHandle _handle;
  bool _disposed = false;

  @override
  void transitionToKeyRatchet(VoiceDaveKeyRatchet keyRatchet) {
    _checkActive();
    final native = _nativeRatchet(keyRatchet);
    _bindings.decryptorTransitionToKeyRatchet(_handle, native.handle);
  }

  @override
  void transitionToPassthrough(bool enabled) {
    _checkActive();
    _bindings.decryptorTransitionToPassthrough(_handle, enabled);
  }

  @override
  List<int> decrypt({
    required DaveMediaType mediaType,
    required List<int> encryptedFrame,
  }) {
    _checkActive();
    return using((arena) {
      final input = NativeDaveBuffers.allocate(arena, encryptedFrame);
      final capacity = _bindings.decryptorGetMaxPlaintextSize(
        _handle,
        _mediaTypeCode(mediaType),
        encryptedFrame.length,
      );
      final output = capacity == 0 ? nullptr : arena<Uint8>(capacity);
      final written = arena<Size>();
      final result = _bindings.decryptorDecrypt(
        _handle,
        _mediaTypeCode(mediaType),
        input,
        encryptedFrame.length,
        output,
        capacity,
        written,
      );
      if (result != 0) {
        throw DaveFrameException(
          _decryptFailure(result),
          operation: 'decryption',
        );
      }
      _checkWrittenSize(written.value, capacity);
      return NativeDaveBuffers.copy(output, written.value);
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bindings.decryptorDestroy(_handle);
    _handle = nullptr;
  }

  void _checkActive() {
    if (_disposed) throw StateError('DAVE decryptor is already disposed');
  }
}

NativeDaveKeyRatchet _nativeRatchet(VoiceDaveKeyRatchet keyRatchet) {
  if (keyRatchet is! NativeDaveKeyRatchet) {
    throw ArgumentError.value(keyRatchet, 'keyRatchet', 'must be native');
  }
  return keyRatchet;
}

void _checkSsrc(int ssrc) {
  if (ssrc < 0 || ssrc > 0xffffffff) {
    throw RangeError.range(ssrc, 0, 0xffffffff, 'ssrc');
  }
}

void _checkWrittenSize(int written, int capacity) {
  if (written < 0 || written > capacity) {
    throw StateError('libdave returned an invalid output size');
  }
}

DaveFrameFailure _encryptFailure(int code) => switch (code) {
  1 => DaveFrameFailure.encryptionFailure,
  2 => DaveFrameFailure.missingKeyRatchet,
  3 => DaveFrameFailure.missingCryptor,
  4 => DaveFrameFailure.tooManyAttempts,
  _ => DaveFrameFailure.unknown,
};

DaveFrameFailure _decryptFailure(int code) => switch (code) {
  1 => DaveFrameFailure.decryptionFailure,
  2 => DaveFrameFailure.missingKeyRatchet,
  3 => DaveFrameFailure.invalidNonce,
  4 => DaveFrameFailure.missingCryptor,
  _ => DaveFrameFailure.unknown,
};

int _mediaTypeCode(DaveMediaType mediaType) => switch (mediaType) {
  DaveMediaType.audio => 0,
  DaveMediaType.video => 1,
};

int _codecCode(DaveMediaCodec codec) => switch (codec) {
  DaveMediaCodec.unknown => 0,
  DaveMediaCodec.opus => 1,
  DaveMediaCodec.vp8 => 2,
  DaveMediaCodec.vp9 => 3,
  DaveMediaCodec.h264 => 4,
  DaveMediaCodec.h265 => 5,
  DaveMediaCodec.av1 => 6,
};
