import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../domain/stream_captures.dart';
import 'screenshot_service.dart';

/// What the window walk saw of one visible top-level window. The walk reads
/// nothing more of a hidden one.
final class WindowFacts {
  const WindowFacts({
    required this.title,
    required this.className,
    required this.isMinimized,
    required this.isCloaked,
    required this.isToolWindow,
    required this.isAppWindow,
    required this.hasOwner,
    required this.isOwnProcess,
    required this.width,
    required this.height,
  });

  final String title;
  final String className;
  final bool isMinimized;

  /// Hidden by the compositor: on another virtual desktop, or a suspended
  /// store app.
  final bool isCloaked;

  /// `WS_EX_TOOLWINDOW`: kept out of the task bar and Alt+Tab.
  final bool isToolWindow;

  /// `WS_EX_APPWINDOW`: asks for the task bar whatever else it is.
  final bool isAppWindow;
  final bool hasOwner;

  /// One of this client's own windows.
  final bool isOwnProcess;
  final int width;
  final int height;

  /// The shell's own windows: the desktop and the task bars.
  static const _shellClasses = {
    'Progman',
    'WorkerW',
    'Shell_TrayWnd',
    'Shell_SecondaryTrayWnd',
  };

  /// Whether the picker offers it: the windows Alt+Tab lists, as Discord's
  /// own picker does, without this client's windows. A minimized window has
  /// no picture to send, so it is left out too.
  bool get isCapturable =>
      !isMinimized &&
      !isCloaked &&
      !isOwnProcess &&
      title.trim().isNotEmpty &&
      width > 0 &&
      height > 0 &&
      (isAppWindow || (!isToolWindow && !hasOwner)) &&
      !_shellClasses.contains(className);
}

typedef _Handle = IntPtr;

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

/// `BITMAPINFOHEADER`. The colour table that follows it in `BITMAPINFO` is
/// empty for a 32-bit picture, so the header alone is passed.
final class _BitmapInfoHeader extends Struct {
  @Uint32()
  external int size;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Uint16()
  external int planes;
  @Uint16()
  external int bitCount;
  @Uint32()
  external int compression;
  @Uint32()
  external int sizeImage;
  @Int32()
  external int xPelsPerMeter;
  @Int32()
  external int yPelsPerMeter;
  @Uint32()
  external int colorsUsed;
  @Uint32()
  external int colorsImportant;
}

/// Lists the windows to share and takes the picker's thumbnails, straight
/// FFI against `user32`, `gdi32` and `dwmapi` as the capture shield does.
///
/// The window walk is quick and runs where it is asked. The thumbnails run
/// on an isolate of their own: a screen capture can wait up to a second, and
/// `PrintWindow` waits on the window's own thread.
final class WindowsCaptureCatalog implements CaptureCatalog {
  WindowsCaptureCatalog() : _user32 = _User32.open();

  final _User32 _user32;

  /// How long the window thumbnails may take before the picker goes on
  /// without them. A window that stops answering would otherwise hold the
  /// picker open.
  static const _windowBudget = Duration(seconds: 2);

  @override
  List<WindowCapture> windows() => _user32.shareableWindows();

  @override
  Future<Map<String, CaptureThumbnail>> thumbnails(
    List<StreamCapture> sources,
  ) => _take(sources);

  /// Static, so the closures handed to the isolates cannot capture `this`
  /// and the native handles it holds.
  static Future<Map<String, CaptureThumbnail>> _take(
    List<StreamCapture> sources,
  ) async {
    final displays = [
      for (final source in sources)
        if (source is DisplayCapture)
          (id: source.sourceId, index: source.index),
    ];
    final windows = [
      for (final source in sources)
        if (source is WindowCapture)
          (id: source.sourceId, handle: source.handle),
    ];
    // The screens are always waited for: each capture behind them is closed
    // before its isolate answers, and the share must not start before then.
    final taken = await Future.wait([
      Isolate.run(() => _screenThumbnails(displays)),
      Isolate.run(
        () => _windowThumbnails(windows),
      ).timeout(_windowBudget, onTimeout: () => const {}),
    ]);
    return {for (final part in taken) ...part};
  }

  static Map<String, CaptureThumbnail> _screenThumbnails(
    List<({String id, int index})> displays,
  ) {
    final screens = NativeScreenshotService();
    return {
      for (final display in displays)
        if (screens.capture(displayIndex: display.index) case final shot?)
          display.id: CaptureThumbnail.fromBgra(
            shot.pixels,
            width: shot.width,
            height: shot.height,
            stride: shot.stride,
          ),
    };
  }

  static Map<String, CaptureThumbnail> _windowThumbnails(
    List<({String id, int handle})> windows,
  ) {
    final user32 = _User32.open();
    return {
      for (final window in windows)
        window.id: ?user32.printWindow(window.handle),
    };
  }
}

/// The Windows calls the catalog makes, looked up once.
final class _User32 {
  _User32._(DynamicLibrary user32, DynamicLibrary gdi32, DynamicLibrary dwmapi)
    : _getWindow = user32
          .lookupFunction<
            _Handle Function(_Handle, Uint32),
            int Function(int, int)
          >('GetWindow'),
      _getDesktopWindow = user32
          .lookupFunction<_Handle Function(), int Function()>(
            'GetDesktopWindow',
          ),
      _isWindowVisible = user32
          .lookupFunction<Int32 Function(_Handle), int Function(int)>(
            'IsWindowVisible',
          ),
      _isIconic = user32
          .lookupFunction<Int32 Function(_Handle), int Function(int)>(
            'IsIconic',
          ),
      _isHung = user32
          .lookupFunction<Int32 Function(_Handle), int Function(int)>(
            'IsHungAppWindow',
          ),
      _getWindowText = user32
          .lookupFunction<
            Int32 Function(_Handle, Pointer<Uint16>, Int32),
            int Function(int, Pointer<Uint16>, int)
          >('GetWindowTextW'),
      _getClassName = user32
          .lookupFunction<
            Int32 Function(_Handle, Pointer<Uint16>, Int32),
            int Function(int, Pointer<Uint16>, int)
          >('GetClassNameW'),
      _getWindowLongPtr = user32
          .lookupFunction<
            IntPtr Function(_Handle, Int32),
            int Function(int, int)
          >('GetWindowLongPtrW'),
      _threadProcess = user32
          .lookupFunction<
            Uint32 Function(_Handle, Pointer<Uint32>),
            int Function(int, Pointer<Uint32>)
          >('GetWindowThreadProcessId'),
      _getWindowRect = user32
          .lookupFunction<
            Int32 Function(_Handle, Pointer<_Rect>),
            int Function(int, Pointer<_Rect>)
          >('GetWindowRect'),
      _getDc = user32
          .lookupFunction<_Handle Function(_Handle), int Function(int)>(
            'GetDC',
          ),
      _releaseDc = user32
          .lookupFunction<
            Int32 Function(_Handle, _Handle),
            int Function(int, int)
          >('ReleaseDC'),
      _printWindow = user32
          .lookupFunction<
            Int32 Function(_Handle, _Handle, Uint32),
            int Function(int, int, int)
          >('PrintWindow'),
      _createCompatibleDc = gdi32
          .lookupFunction<_Handle Function(_Handle), int Function(int)>(
            'CreateCompatibleDC',
          ),
      _createCompatibleBitmap = gdi32
          .lookupFunction<
            _Handle Function(_Handle, Int32, Int32),
            int Function(int, int, int)
          >('CreateCompatibleBitmap'),
      _selectObject = gdi32
          .lookupFunction<
            _Handle Function(_Handle, _Handle),
            int Function(int, int)
          >('SelectObject'),
      _getDiBits = gdi32
          .lookupFunction<
            Int32 Function(
              _Handle,
              _Handle,
              Uint32,
              Uint32,
              Pointer<Uint8>,
              Pointer<_BitmapInfoHeader>,
              Uint32,
            ),
            int Function(
              int,
              int,
              int,
              int,
              Pointer<Uint8>,
              Pointer<_BitmapInfoHeader>,
              int,
            )
          >('GetDIBits'),
      _deleteObject = gdi32
          .lookupFunction<Int32 Function(_Handle), int Function(int)>(
            'DeleteObject',
          ),
      _deleteDc = gdi32
          .lookupFunction<Int32 Function(_Handle), int Function(int)>(
            'DeleteDC',
          ),
      _dwmGetWindowAttribute = dwmapi
          .lookupFunction<
            Int32 Function(_Handle, Uint32, Pointer<Void>, Uint32),
            int Function(int, int, Pointer<Void>, int)
          >('DwmGetWindowAttribute'),
      _ownProcess = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<Uint32 Function(), int Function()>(
            'GetCurrentProcessId',
          )();

  factory _User32.open() => _User32._(
    DynamicLibrary.open('user32.dll'),
    DynamicLibrary.open('gdi32.dll'),
    DynamicLibrary.open('dwmapi.dll'),
  );

  static const _gwChild = 5;
  static const _gwHwndNext = 2;
  static const _gwOwner = 4;
  static const _gwlExStyle = -20;
  static const _wsExToolWindow = 0x00000080;
  static const _wsExAppWindow = 0x00040000;
  static const _dwmwaCloaked = 14;

  /// Draws the whole window, including content Direct3D or DirectComposition
  /// put there, rather than only what GDI painted.
  static const _pwRenderFullContent = 0x00000002;
  static const _dibRgbColors = 0;
  static const _textCapacity = 256;

  final int Function(int, int) _getWindow;
  final int Function() _getDesktopWindow;
  final int Function(int) _isWindowVisible;
  final int Function(int) _isIconic;
  final int Function(int) _isHung;
  final int Function(int, Pointer<Uint16>, int) _getWindowText;
  final int Function(int, Pointer<Uint16>, int) _getClassName;
  final int Function(int, int) _getWindowLongPtr;
  final int Function(int, Pointer<Uint32>) _threadProcess;
  final int Function(int, Pointer<_Rect>) _getWindowRect;
  final int Function(int) _getDc;
  final int Function(int, int) _releaseDc;
  final int Function(int, int, int) _printWindow;
  final int Function(int) _createCompatibleDc;
  final int Function(int, int, int) _createCompatibleBitmap;
  final int Function(int, int) _selectObject;
  final int Function(
    int,
    int,
    int,
    int,
    Pointer<Uint8>,
    Pointer<_BitmapInfoHeader>,
    int,
  )
  _getDiBits;
  final int Function(int) _deleteObject;
  final int Function(int) _deleteDc;
  final int Function(int, int, Pointer<Void>, int) _dwmGetWindowAttribute;
  final int _ownProcess;

  /// The top-level windows the picker offers, front first.
  List<WindowCapture> shareableWindows() {
    final text = calloc<Uint16>(_textCapacity);
    final className = calloc<Uint16>(_textCapacity);
    final process = calloc<Uint32>();
    final cloaked = calloc<Int32>();
    final rect = calloc<_Rect>();
    try {
      final found = <WindowCapture>[];
      // GW_CHILD from the desktop is the first top-level window; GW_HWNDNEXT
      // walks the rest in z-order.
      for (
        var window = _getWindow(_getDesktopWindow(), _gwChild);
        window != 0;
        window = _getWindow(window, _gwHwndNext)
      ) {
        // Most top-level windows are hidden; nothing more is read of those.
        if (_isWindowVisible(window) == 0) continue;
        process.value = 0;
        _threadProcess(window, process);
        cloaked.value = 0;
        _dwmGetWindowAttribute(window, _dwmwaCloaked, cloaked.cast(), 4);
        rect.ref
          ..left = 0
          ..top = 0
          ..right = 0
          ..bottom = 0;
        _getWindowRect(window, rect);
        final exStyle = _getWindowLongPtr(window, _gwlExStyle);
        final facts = WindowFacts(
          title: _read(text, _getWindowText(window, text, _textCapacity)),
          className: _read(
            className,
            _getClassName(window, className, _textCapacity),
          ),
          isMinimized: _isIconic(window) != 0,
          isCloaked: cloaked.value != 0,
          isToolWindow: exStyle & _wsExToolWindow != 0,
          isAppWindow: exStyle & _wsExAppWindow != 0,
          hasOwner: _getWindow(window, _gwOwner) != 0,
          isOwnProcess: process.value == _ownProcess,
          width: rect.ref.right - rect.ref.left,
          height: rect.ref.bottom - rect.ref.top,
        );
        if (facts.isCapturable) {
          found.add(WindowCapture(handle: window, name: facts.title.trim()));
        }
      }
      return found;
    } finally {
      calloc
        ..free(text)
        ..free(className)
        ..free(process)
        ..free(cloaked)
        ..free(rect);
    }
  }

  /// A thumbnail of [window], or null when it is gone, not answering, or
  /// would not draw.
  CaptureThumbnail? printWindow(int window) {
    if (_isHung(window) != 0) return null;
    final rect = calloc<_Rect>();
    final info = calloc<_BitmapInfoHeader>();
    final screen = _getDc(0);
    final memory = _createCompatibleDc(screen);
    var bitmap = 0;
    Pointer<Uint8> pixels = nullptr;
    try {
      if (_getWindowRect(window, rect) == 0) return null;
      final width = rect.ref.right - rect.ref.left;
      final height = rect.ref.bottom - rect.ref.top;
      if (width <= 0 || height <= 0) return null;
      bitmap = _createCompatibleBitmap(screen, width, height);
      if (bitmap == 0) return null;
      final previous = _selectObject(memory, bitmap);
      final drawn = _printWindow(window, memory, _pwRenderFullContent) != 0;
      // GetDIBits wants the bitmap out of any device context.
      _selectObject(memory, previous);
      if (!drawn) return null;

      info.ref
        ..size = sizeOf<_BitmapInfoHeader>()
        ..width = width
        // Negative: rows from the top, as CaptureThumbnail reads them.
        ..height = -height
        ..planes = 1
        ..bitCount = 32;
      final length = width * height * 4;
      pixels = calloc<Uint8>(length);
      final rows = _getDiBits(
        memory,
        bitmap,
        0,
        height,
        pixels,
        info,
        _dibRgbColors,
      );
      if (rows != height) return null;
      return CaptureThumbnail.fromBgra(
        Uint8List.fromList(pixels.asTypedList(length)),
        width: width,
        height: height,
        stride: width * 4,
      );
    } finally {
      if (pixels != nullptr) calloc.free(pixels);
      if (bitmap != 0) _deleteObject(bitmap);
      _deleteDc(memory);
      _releaseDc(0, screen);
      calloc
        ..free(rect)
        ..free(info);
    }
  }

  static String _read(Pointer<Uint16> buffer, int length) =>
      length <= 0 ? '' : String.fromCharCodes(buffer.asTypedList(length));
}
