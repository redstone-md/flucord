import 'package:flutter/foundation.dart';

import '../domain/stream_quality.dart';
import '../domain/video_capture_hub.dart';

/// Stream quality as the settings plane sees it: kept between runs, and fed
/// to the capture module so the next share or camera runs at it.
///
/// A change does not touch a capture that is already running: the encoder can
/// only run one set of settings, and re-encoding mid-stream is a restart of
/// the picture. What is on screen keeps what it started with.
final class StreamQualityController extends ChangeNotifier {
  StreamQualityController(this._repository, {required VideoCaptureHub capture})
    : _capture = capture;

  final StreamQualityRepository _repository;
  final VideoCaptureHub _capture;

  StreamQualitySettings _settings = const StreamQualitySettings();
  bool _loaded = false;

  StreamQualitySettings get settings => _settings;

  int get shareBitrate => _settings.shareBitrate;

  int get cameraBitrate => _settings.cameraBitrate;

  StreamResolution get shareResolution => _settings.shareResolution;

  int get shareFrameRate => _settings.shareFrameRate;

  /// Why the last change did not reach the file, where it did not.
  ///
  /// The change is still applied for this session; what is lost is the next
  /// restart, and saying so out loud beats a settings screen that quietly
  /// forgets.
  Object? get writeError => _writeError;
  Object? _writeError;

  Future<void> load() async {
    if (_loaded) return;
    _settings = await _repository.load();
    _loaded = true;
    _capture.quality = _settings;
    _notify();
  }

  Future<void> setShareBitrate(int bitrate) =>
      _set(_settings.copyWith(shareBitrate: bitrate));

  Future<void> setCameraBitrate(int bitrate) =>
      _set(_settings.copyWith(cameraBitrate: bitrate));

  Future<void> setShareResolution(StreamResolution resolution) =>
      _set(_settings.copyWith(shareResolution: resolution));

  Future<void> setShareFrameRate(int frameRate) =>
      _set(_settings.copyWith(shareFrameRate: frameRate));

  Future<void> _set(StreamQualitySettings settings) async {
    if (!settings.isValid || settings == _settings) return;
    _settings = settings;
    _capture.quality = settings;
    _notify();
    try {
      await _repository.save(settings);
      _writeError = null;
    } on Object catch (error) {
      _writeError = error;
      _notify();
    }
  }

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
