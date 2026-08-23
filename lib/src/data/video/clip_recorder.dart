import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/video_capture_hub.dart';
import '../../domain/video_encoder.dart';
import 'native_video_bindings.dart';

/// Where a saved clip ended up, or why it did not.
final class ClipResult {
  const ClipResult.saved(this.path) : failure = null;
  const ClipResult.failed(this.failure) : path = null;

  final String? path;
  final ClipFailure? failure;

  bool get isSaved => path != null;
}

enum ClipFailure {
  /// No native writer in this build.
  unsupported,

  /// Nothing worth saving is in the buffer yet.
  empty,

  /// The writer or the file system refused it.
  write,
}

/// The last few seconds of what the machine's capture encoded.
///
/// Discord's `SAVE_CLIP`: a clip is not a recording somebody started, it is
/// the recording that was already running. Frames are kept as they were
/// encoded rather than re-encoded on save — they were compressed once
/// already, and a second pass would be slower and worse.
abstract interface class ClipRecorder {
  bool get isSupported;

  /// How much is buffered right now.
  Duration get buffered;

  /// Follows the capture module's frames until [detach].
  void attach(VideoCaptureHub capture);

  void detach();

  /// Writes what is buffered, answering where it went.
  Future<ClipResult> save();
}

/// A recorder in a build with no writer. Never pretends to have kept anything.
final class UnavailableClipRecorder implements ClipRecorder {
  const UnavailableClipRecorder();

  @override
  bool get isSupported => false;

  @override
  Duration get buffered => Duration.zero;

  @override
  void attach(VideoCaptureHub capture) {}

  @override
  void detach() {}

  @override
  Future<ClipResult> save() async =>
      const ClipResult.failed(ClipFailure.unsupported);
}

/// A ring buffer of encoded frames, written out through Media Foundation.
final class NativeClipRecorder implements ClipRecorder {
  NativeClipRecorder({
    NativeVideoBindings? bindings,
    ClipWriterBindings? writer,
    Future<Directory> Function()? directory,
    DateTime Function()? now,
    this.window = const Duration(seconds: 30),
  }) : _writer = writer ?? (bindings ?? _openLibrary())?.clip,
       _directory = directory ?? _documents,
       _now = now ?? DateTime.now;

  static NativeVideoBindings? _openLibrary() {
    if (!Platform.isWindows) return null;
    try {
      return NativeVideoBindings(DynamicLibrary.open('flucord_video.dll'));
    } on Object {
      return null;
    }
  }

  static Future<Directory> _documents() async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}'
          '${Platform.pathSeparator}Flucord');

  /// How much is kept. Discord's own clip length is a setting; this is the
  /// default it ships with.
  final Duration window;

  final ClipWriterBindings? _writer;
  final Future<Directory> Function() _directory;
  final DateTime Function() _now;

  final Queue<EncodedVideoFrame> _frames = Queue<EncodedVideoFrame>();
  StreamSubscription<EncodedVideoFrame>? _subscription;
  VideoCaptureHub? _capture;

  /// What the frames in the buffer were encoded at. Set when they arrived,
  /// because only the running capture knows, and kept after it stops: a clip
  /// is saved after the session it belongs to.
  VideoEncoderSettings? _settings;

  @override
  bool get isSupported => _writer != null;

  @override
  Duration get buffered => _frames.isEmpty
      ? Duration.zero
      : _frames.last.timestamp - _frames.first.timestamp;

  @override
  void attach(VideoCaptureHub capture) {
    detach();
    _capture = capture;
    _subscription = capture.frames.listen(_accept);
  }

  @override
  void detach() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _capture = null;
    _frames.clear();
    _settings = null;
  }

  void _accept(EncodedVideoFrame frame) {
    final settings = _capture?.settings;
    if (settings != null && settings != _settings) {
      // A new capture began under different settings: the buffer holds
      // pictures of another size or source, and one file cannot mix them.
      _frames.clear();
      _settings = settings;
    }
    _frames.add(frame);
    _trim();
  }

  /// Drops what has aged out, but never past the oldest keyframe still needed.
  ///
  /// A clip that began on a delta frame decodes to nothing: the picture it is
  /// a difference from was thrown away.
  void _trim() {
    while (_frames.length > 1 &&
        _frames.last.timestamp - _frames.first.timestamp > window) {
      // Only drop the front while something behind it can still open a clip.
      final hasLaterKeyframe = _frames
          .skip(1)
          .any((frame) => frame.isKeyframe);
      if (!hasLaterKeyframe) return;
      _frames.removeFirst();
    }
  }

  /// The frames a clip would be made of: from the oldest keyframe onwards.
  List<EncodedVideoFrame> get clipFrames {
    final frames = _frames.toList(growable: false);
    final start = frames.indexWhere((frame) => frame.isKeyframe);
    return start < 0 ? const [] : frames.sublist(start);
  }

  @override
  Future<ClipResult> save() async {
    final writer = _writer;
    final settings = _settings;
    if (writer == null) {
      return const ClipResult.failed(ClipFailure.unsupported);
    }
    // No settings means no frame ever arrived, which means there is nothing
    // worth saving rather than something that failed to write.
    if (settings == null) return const ClipResult.failed(ClipFailure.empty);
    final frames = clipFrames;
    if (frames.isEmpty) return const ClipResult.failed(ClipFailure.empty);

    try {
      final directory = await _directory();
      await directory.create(recursive: true);
      final path =
          '${directory.path}${Platform.pathSeparator}${fileNameFor(_now())}';
      return _write(writer, settings, frames, path)
          ? ClipResult.saved(path)
          : const ClipResult.failed(ClipFailure.write);
    } on Object {
      return const ClipResult.failed(ClipFailure.write);
    }
  }

  bool _write(
    ClipWriterBindings writer,
    VideoEncoderSettings settings,
    List<EncodedVideoFrame> frames,
    String path,
  ) {
    final pathPointer = path.toNativeUtf8();
    final out = calloc<Pointer<Void>>();
    try {
      if (writer.open(
            pathPointer,
            settings.width,
            settings.height,
            settings.framesPerSecond,
            settings.bitrate,
            out,
          ) !=
          0) {
        return false;
      }
      final clip = out.value;
      // Timestamps are rebased on the first frame: the file starts at zero,
      // not at whenever the encoder happened to have been running since.
      final origin = frames.first.timestamp;
      var wrote = true;
      for (final frame in frames) {
        final bytes = calloc<Uint8>(frame.bytes.length);
        try {
          bytes.asTypedList(frame.bytes.length).setAll(0, frame.bytes);
          if (writer.write(
                clip,
                bytes,
                frame.bytes.length,
                (frame.timestamp - origin).inMicroseconds,
                frame.isKeyframe ? 1 : 0,
              ) !=
              0) {
            wrote = false;
            break;
          }
        } finally {
          calloc.free(bytes);
        }
      }
      // Closed either way: a file left unfinalised is one no player opens.
      final closed = writer.close(clip) == 0;
      return wrote && closed;
    } finally {
      calloc
        ..free(pathPointer)
        ..free(out);
    }
  }

  /// The name a clip is saved under, sortable and second-resolution.
  static String fileNameFor(DateTime when) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'flucord-clip-${when.year}${two(when.month)}${two(when.day)}'
        '-${two(when.hour)}${two(when.minute)}${two(when.second)}.mp4';
  }
}
