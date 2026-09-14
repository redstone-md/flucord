import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// The basenames of the executables running on this machine.
abstract interface class GameProcessScanner {
  /// Whether this platform can scan at all.
  bool get isSupported;

  /// Scans once and answers the executable basenames it saw. Duplicates are
  /// not folded here: the mapper keys on the name, so two copies of one
  /// executable change nothing.
  Set<String> runningExecutableBasenames();
}

/// A scanner on a platform that has none. Sees nothing, never pretends.
final class UnavailableGameProcessScanner implements GameProcessScanner {
  const UnavailableGameProcessScanner();

  @override
  bool get isSupported => false;

  @override
  Set<String> runningExecutableBasenames() => const {};
}

typedef _EnumProcessesNative =
    Int32 Function(Pointer<Uint32>, Uint32, Pointer<Uint32>);
typedef _EnumProcessesDart =
    int Function(Pointer<Uint32>, int, Pointer<Uint32>);
typedef _OpenProcessNative = Pointer<Void> Function(Uint32, Int32, Uint32);
typedef _OpenProcessDart = Pointer<Void> Function(int, int, int);
typedef _ModuleBaseNameNative =
    Uint32 Function(Pointer<Void>, Pointer<Void>, Pointer<Uint16>, Uint32);
typedef _ModuleBaseNameDart =
    int Function(Pointer<Void>, Pointer<Void>, Pointer<Uint16>, int);
typedef _CloseHandleNative = Int32 Function(Pointer<Void>);
typedef _CloseHandleDart = int Function(Pointer<Void>);

/// The running processes through `psapi.dll`.
///
/// Straight FFI rather than a package: one process walk and one name lookup,
/// both in the Windows API since XP, and a dependency added for that would be
/// more to keep current than to write.
final class WindowsGameProcessScanner implements GameProcessScanner {
  WindowsGameProcessScanner()
    : this.withLibraries(
        kernel32: Platform.isWindows ? _open('kernel32.dll') : null,
        psapi: Platform.isWindows ? _open('psapi.dll') : null,
      );

  /// The libraries handed in rather than opened.
  ///
  /// Null means the library is genuinely absent, which is the case a test has
  /// to be able to state: passing null to the ordinary constructor would only
  /// mean "open it yourself", and on Windows it would.
  const WindowsGameProcessScanner.withLibraries({
    required DynamicLibrary? kernel32,
    required DynamicLibrary? psapi,
  }) : _kernel32 = kernel32,
       _psapi = psapi;

  static const int processQueryInformation = 0x0400;
  static const int processVmRead = 0x0010;

  static DynamicLibrary? _open(String name) {
    try {
      return DynamicLibrary.open(name);
    } on Object {
      return null;
    }
  }

  final DynamicLibrary? _kernel32;
  final DynamicLibrary? _psapi;

  @override
  bool get isSupported => _kernel32 != null && _psapi != null;

  @override
  Set<String> runningExecutableBasenames() {
    final psapi = _psapi;
    final kernel32 = _kernel32;
    if (psapi == null || kernel32 == null) return const {};
    final enumProcesses = psapi
        .lookupFunction<_EnumProcessesNative, _EnumProcessesDart>(
          'EnumProcesses',
        );
    final openProcess = kernel32
        .lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
    final closeHandle = kernel32
        .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
    final moduleBaseName = psapi
        .lookupFunction<_ModuleBaseNameNative, _ModuleBaseNameDart>(
          'GetModuleBaseNameW',
        );

    final capacity = 2048;
    final ids = calloc<Uint32>(capacity);
    final bytesReturned = calloc<Uint32>();
    final name = calloc<Uint16>(512);
    final names = <String>{};
    try {
      if (enumProcesses(ids, capacity * 4, bytesReturned) == 0) return const {};
      final count = bytesReturned.value ~/ 4;
      for (var index = 0; index < count; index++) {
        final processId = ids[index];
        // PID 0 is the system idle process and PID 4 is the kernel; neither
        // opens, and asking would be one syscall per scan for nothing.
        if (processId <= 4) continue;
        final process = openProcess(
          processQueryInformation | processVmRead,
          0,
          processId,
        );
        if (process == nullptr) continue;
        try {
          final length = moduleBaseName(process, nullptr, name, 512);
          if (length <= 0 || length >= 512) continue;
          names.add(String.fromCharCodes(name.asTypedList(length)));
        } finally {
          closeHandle(process);
        }
      }
      return Set.unmodifiable(names);
    } finally {
      calloc.free(ids);
      calloc.free(bytesReturned);
      calloc.free(name);
    }
  }
}

/// The file name of a path, on either separator.
///
/// Public because the mapping rule shares it: an executable Discord lists by
/// its full path and a process the scanner reports by its name meet on the
/// basename.
@visibleForTesting
String executableBasename(String path) {
  final last = path.lastIndexOf('\\') >= path.lastIndexOf('/')
      ? path.lastIndexOf('\\')
      : path.lastIndexOf('/');
  return last < 0 ? path : path.substring(last + 1);
}
