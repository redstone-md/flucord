import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

/// The window that floats over a game.
///
/// Deliberately not an injected overlay. Discord's own draws inside the other
/// process by hooking its presentation, which is what anti-cheat systems watch
/// for; a layered click-through window of our own shows the same thing over
/// any windowed or borderless-fullscreen game without touching it. Exclusive
/// fullscreen is the case it cannot cover, and the client says so rather than
/// leaving somebody to wonder why nothing appeared.
abstract interface class VoiceOverlay {
  bool get isSupported;
  bool get isVisible;

  /// Draws [speakers], creating the window if needed. Answers whether the
  /// picture reached the screen.
  Future<bool> show(List<OverlaySpeaker> speakers);

  void hide();
  void close();
}

/// One row of the overlay.
final class OverlaySpeaker {
  const OverlaySpeaker({required this.name, required this.isSpeaking});

  final String name;
  final bool isSpeaking;
}

/// An overlay on a platform that has no window for it.
final class UnavailableVoiceOverlay implements VoiceOverlay {
  const UnavailableVoiceOverlay();

  @override
  bool get isSupported => false;

  @override
  bool get isVisible => false;

  @override
  Future<bool> show(List<OverlaySpeaker> speakers) async => false;

  @override
  void hide() {}

  @override
  void close() {}
}

typedef _UpdateDart = int Function(Pointer<Uint8>, int, int);

/// `UpdateLayeredWindow` through `flucord_overlay.dll`.
final class WindowsVoiceOverlay implements VoiceOverlay {
  WindowsVoiceOverlay({DynamicLibrary? library, OverlayPainter? painter})
    : this.withLibrary(
        Platform.isWindows ? _open() : null,
        painter: painter,
      );

  /// The module handed in rather than opened, so a test can state that it is
  /// genuinely absent.
  WindowsVoiceOverlay.withLibrary(this._library, {OverlayPainter? painter})
    : _painter = painter ?? paintOverlay;

  static DynamicLibrary? _open() {
    try {
      return DynamicLibrary.open('flucord_overlay.dll');
    } on Object {
      return null;
    }
  }

  final DynamicLibrary? _library;
  final OverlayPainter _painter;
  bool _visible = false;

  @override
  bool get isSupported => _library != null;

  @override
  bool get isVisible => _visible;

  @override
  Future<bool> show(List<OverlaySpeaker> speakers) async {
    final library = _library;
    if (library == null) return false;
    if (speakers.isEmpty) {
      // Nothing to say is not a blank rectangle over somebody's game.
      hide();
      return false;
    }
    final picture = await _painter(speakers);
    if (picture == null) return false;

    final showWindow = library
        .lookupFunction<
          Int32 Function(Int32, Int32),
          int Function(int, int)
        >('flucord_overlay_show');
    if (showWindow(24, 24) != 0) return false;

    final update = library
        .lookupFunction<
          Int32 Function(Pointer<Uint8>, Int32, Int32),
          _UpdateDart
        >('flucord_overlay_update');
    final buffer = calloc<Uint8>(picture.pixels.length);
    try {
      buffer.asTypedList(picture.pixels.length).setAll(0, picture.pixels);
      if (update(buffer, picture.width, picture.height) != 0) return false;
    } finally {
      calloc.free(buffer);
    }
    _visible = true;
    return true;
  }

  @override
  void hide() {
    _library?.lookupFunction<Void Function(), void Function()>(
      'flucord_overlay_hide',
    )();
    _visible = false;
  }

  @override
  void close() {
    _library?.lookupFunction<Void Function(), void Function()>(
      'flucord_overlay_close',
    )();
    _visible = false;
  }
}

/// A drawn overlay, premultiplied and ready for the window.
final class OverlayPicture {
  const OverlayPicture({
    required this.pixels,
    required this.width,
    required this.height,
  });

  final Uint8List pixels;
  final int width;
  final int height;
}

typedef OverlayPainter =
    Future<OverlayPicture?> Function(List<OverlaySpeaker> speakers);

/// Draws the speaker list the way the rest of the client would.
///
/// Rendered here rather than in C++ so the overlay looks like Flucord: a
/// second drawing stack would be a second one to keep in step with the theme.
Future<OverlayPicture?> paintOverlay(List<OverlaySpeaker> speakers) async {
  const rowHeight = 28.0;
  const width = 220.0;
  final height = rowHeight * speakers.length + 12;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final background = Paint()..color = const Color(0xCC1B1D22);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      const Radius.circular(8),
    ),
    background,
  );

  for (var index = 0; index < speakers.length; index++) {
    final speaker = speakers[index];
    final top = 6 + index * rowHeight;
    canvas.drawCircle(
      Offset(18, top + rowHeight / 2),
      6,
      Paint()
        ..color = speaker.isSpeaking
            ? const Color(0xFF43B581)
            : const Color(0x66FFFFFF),
    );
    final text = TextPainter(
      text: TextSpan(
        text: speaker.name,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width - 40);
    text.paint(canvas, Offset(32, top + (rowHeight - text.height) / 2));
  }

  final image = await recorder.endRecording().toImage(
    width.round(),
    height.round(),
  );
  try {
    final data = await image.toByteData(
      // Premultiplied is what UpdateLayeredWindow expects; straight alpha
      // draws every edge with a dark fringe around it.
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) return null;
    return OverlayPicture(
      pixels: premultipliedBgraFromRgba(data.buffer.asUint8List()),
      width: image.width,
      height: image.height,
    );
  } finally {
    image.dispose();
  }
}

/// Converts straight RGBA into the premultiplied BGRA the window wants.
Uint8List premultipliedBgraFromRgba(Uint8List rgba) {
  final out = Uint8List(rgba.length);
  for (var index = 0; index < rgba.length; index += 4) {
    final alpha = rgba[index + 3];
    int scale(int value) => alpha == 255 ? value : (value * alpha) ~/ 255;
    out[index] = scale(rgba[index + 2]);
    out[index + 1] = scale(rgba[index + 1]);
    out[index + 2] = scale(rgba[index]);
    out[index + 3] = alpha;
  }
  return out;
}
