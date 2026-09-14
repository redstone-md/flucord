import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../domain/voice_dave.dart';
import 'native_dave_bindings.dart';
import 'native_dave_buffers.dart';
import 'native_dave_media.dart';

final class NativeDaveService implements VoiceDaveService {
  NativeDaveService._(this._bindings);

  factory NativeDaveService.open({String libraryPath = 'libdave.dll'}) =>
      NativeDaveService._(NativeDaveBindings(DynamicLibrary.open(libraryPath)));

  final NativeDaveBindings _bindings;

  @override
  int get maxProtocolVersion => _bindings.maxSupportedProtocolVersion();

  @override
  VoiceDaveSession createSession({
    required int protocolVersion,
    required String channelId,
    required String selfUserId,
  }) {
    if (protocolVersion <= 0 || protocolVersion > maxProtocolVersion) {
      throw RangeError.range(
        protocolVersion,
        1,
        maxProtocolVersion,
        'protocolVersion',
      );
    }
    final groupId = int.tryParse(channelId);
    final userId = int.tryParse(selfUserId);
    if (groupId == null || groupId <= 0 || userId == null || userId <= 0) {
      throw const FormatException('DAVE requires numeric Discord snowflakes');
    }
    return NativeDaveSession._(
      _bindings,
      protocolVersion: protocolVersion,
      groupId: groupId,
      selfUserId: selfUserId,
    );
  }

  @override
  VoiceDaveEncryptor createEncryptor() => NativeDaveEncryptor.create(_bindings);

  @override
  VoiceDaveDecryptor createDecryptor() => NativeDaveDecryptor.create(_bindings);
}

final class NativeDaveSession implements VoiceDaveSession {
  NativeDaveSession._(
    this._bindings, {
    required int protocolVersion,
    required int groupId,
    required String selfUserId,
  }) {
    _handle = _bindings.sessionCreate(
      nullptr,
      nullptr.cast(),
      NativeDaveBindings.failureCallback,
      nullptr,
    );
    if (_handle == nullptr) {
      throw StateError('libdave failed to create an MLS session');
    }
    using((arena) {
      _bindings.sessionInit(
        _handle,
        protocolVersion,
        groupId,
        selfUserId.toNativeUtf8(allocator: arena),
      );
    });
  }

  final NativeDaveBindings _bindings;
  late DaveSessionHandle _handle;
  bool _disposed = false;

  @override
  int get protocolVersion {
    _checkActive();
    return _bindings.sessionGetProtocolVersion(_handle);
  }

  @override
  void setProtocolVersion(int version) {
    _checkActive();
    if (version < 0 || version > _bindings.maxSupportedProtocolVersion()) {
      throw RangeError.range(
        version,
        0,
        _bindings.maxSupportedProtocolVersion(),
        'version',
      );
    }
    _bindings.sessionSetProtocolVersion(_handle, version);
  }

  @override
  void setExternalSender(List<int> package) {
    _checkActive();
    _withBytes(package, (pointer, length) {
      _bindings.sessionSetExternalSender(_handle, pointer, length);
    });
  }

  @override
  List<int> createKeyPackage() {
    _checkActive();
    return using((arena) {
      final output = arena<Pointer<Uint8>>();
      final length = arena<Size>();
      _bindings.sessionGetKeyPackage(_handle, output, length);
      return _takeBytes(output.value, length.value);
    });
  }

  @override
  List<int> processProposals({
    required List<int> proposals,
    required List<String> recognizedUserIds,
  }) {
    _checkActive();
    return using((arena) {
      final input = _allocateBytes(arena, proposals);
      final users = _allocateUsers(arena, recognizedUserIds);
      final output = arena<Pointer<Uint8>>();
      final outputLength = arena<Size>();
      _bindings.sessionProcessProposals(
        _handle,
        input,
        proposals.length,
        users,
        recognizedUserIds.length,
        output,
        outputLength,
      );
      return _takeBytes(output.value, outputLength.value);
    });
  }

  @override
  DaveCommitResult processCommit(List<int> commit) {
    _checkActive();
    final result = _withBytes(
      commit,
      (pointer, length) =>
          _bindings.sessionProcessCommit(_handle, pointer, length),
    );
    if (result == nullptr) return _failedResult;
    try {
      if (_bindings.commitResultIsFailed(result)) return _failedResult;
      if (_bindings.commitResultIsIgnored(result)) {
        return const DaveCommitResult(
          status: DaveCommitStatus.ignored,
          rosterUserIds: [],
        );
      }
      return DaveCommitResult(
        status: DaveCommitStatus.applied,
        rosterUserIds: _commitRoster(result),
      );
    } finally {
      _bindings.commitResultDestroy(result);
    }
  }

  @override
  DaveCommitResult processWelcome({
    required List<int> welcome,
    required List<String> recognizedUserIds,
  }) {
    _checkActive();
    final result = using((arena) {
      final input = _allocateBytes(arena, welcome);
      final users = _allocateUsers(arena, recognizedUserIds);
      return _bindings.sessionProcessWelcome(
        _handle,
        input,
        welcome.length,
        users,
        recognizedUserIds.length,
      );
    });
    if (result == nullptr) return _failedResult;
    try {
      return DaveCommitResult(
        status: DaveCommitStatus.applied,
        rosterUserIds: _welcomeRoster(result),
      );
    } finally {
      _bindings.welcomeResultDestroy(result);
    }
  }

  @override
  VoiceDaveKeyRatchet getKeyRatchet(String userId) {
    _checkActive();
    final numericUserId = int.tryParse(userId);
    if (numericUserId == null || numericUserId <= 0) {
      throw const FormatException('DAVE requires a numeric Discord user ID');
    }
    final handle = using(
      (arena) => _bindings.sessionGetKeyRatchet(
        _handle,
        userId.toNativeUtf8(allocator: arena),
      ),
    );
    if (handle == nullptr) {
      throw StateError('DAVE key ratchet is unavailable for user $userId');
    }
    return NativeDaveKeyRatchet(_bindings, handle);
  }

  List<String> _commitRoster(DaveResultHandle result) => _readRoster(
    (output, length) => _bindings.commitResultGetRoster(result, output, length),
  );

  List<String> _welcomeRoster(DaveResultHandle result) => _readRoster(
    (output, length) =>
        _bindings.welcomeResultGetRoster(result, output, length),
  );

  List<String> _readRoster(
    void Function(Pointer<Pointer<Uint64>>, Pointer<Size>) read,
  ) => using((arena) {
    final output = arena<Pointer<Uint64>>();
    final length = arena<Size>();
    read(output, length);
    final pointer = output.value;
    if (pointer == nullptr || length.value == 0) return const <String>[];
    try {
      return List<String>.unmodifiable(
        pointer.asTypedList(length.value).map((id) => id.toString()),
      );
    } finally {
      _bindings.free(pointer.cast());
    }
  });

  List<int> _takeBytes(Pointer<Uint8> pointer, int length) {
    if (pointer == nullptr || length == 0) return const [];
    try {
      return List<int>.unmodifiable(pointer.asTypedList(length));
    } finally {
      _bindings.free(pointer.cast());
    }
  }

  T _withBytes<T>(List<int> bytes, T Function(Pointer<Uint8>, int) action) =>
      using((arena) => action(_allocateBytes(arena, bytes), bytes.length));

  Pointer<Uint8> _allocateBytes(Allocator allocator, List<int> bytes) {
    return NativeDaveBuffers.allocate(allocator, bytes);
  }

  Pointer<Pointer<Utf8>> _allocateUsers(
    Allocator allocator,
    List<String> users,
  ) {
    if (users.isEmpty) return nullptr;
    final pointers = allocator<Pointer<Utf8>>(users.length);
    for (var index = 0; index < users.length; index++) {
      pointers[index] = users[index].toNativeUtf8(allocator: allocator);
    }
    return pointers;
  }

  @override
  void reset() {
    _checkActive();
    _bindings.sessionReset(_handle);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bindings.sessionDestroy(_handle);
    _handle = nullptr;
  }

  void _checkActive() {
    if (_disposed) throw StateError('DAVE session is already disposed');
  }
}

const _failedResult = DaveCommitResult(
  status: DaveCommitStatus.failed,
  rosterUserIds: [],
);
