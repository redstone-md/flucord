import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../application/voice_pcm_framer.dart';
import '../domain/voice_audio.dart';
import '../domain/voice_media.dart';
import '../domain/voice_message_recorder.dart';
import 'ogg_opus_muxer.dart';
import 'voice_message_pcm_capture.dart';

typedef VoiceMessageClock = DateTime Function();
typedef VoiceMessageDirectoryProvider = Future<Directory> Function();

final class NativeVoiceMessageRecorder implements VoiceMessageRecorder {
  NativeVoiceMessageRecorder(
    this._codecFactory, {
    VoiceMessagePcmCapture? capture,
    VoiceMessageClock? clock,
    VoiceMessageDirectoryProvider? directoryProvider,
  }) : _capture = capture ?? RecordVoiceMessagePcmCapture(),
       _clock = clock ?? DateTime.now,
       _directoryProvider = directoryProvider ?? getTemporaryDirectory;

  static const int _framesPerWaveformSample = 5;
  static const int _maxWaveformSamples = 256;

  final VoiceOpusCodecFactory _codecFactory;
  final VoiceMessagePcmCapture _capture;
  final VoiceMessageClock _clock;
  final VoiceMessageDirectoryProvider _directoryProvider;
  final VoicePcmFramer _framer = VoicePcmFramer();
  final StreamController<VoiceMessageRecordingProgress> _progress =
      StreamController.broadcast();
  final Set<String> _ownedPaths = {};
  final List<Uint8List> _packets = [];
  final List<double> _waveformPeaks = [];

  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _streamDone;
  VoiceOpusEncoder? _encoder;
  Object? _captureError;
  bool _isRecording = false;
  bool _disposed = false;
  int _frameCount = 0;
  int _peakFrameCount = 0;
  double _peak = 0;
  int _fileSequence = 0;

  @override
  Stream<VoiceMessageRecordingProgress> get progress => _progress.stream;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<void> start() async {
    if (_disposed) throw StateError('Voice message recorder is disposed');
    if (_isRecording) throw StateError('A voice message is already recording');
    _resetSession();
    _encoder = _codecFactory.createEncoder();
    try {
      final stream = await _capture.start();
      _streamDone = Completer<void>();
      _isRecording = true;
      _subscription = stream.listen(
        _handlePcm,
        onError: _handleCaptureError,
        onDone: _handleStreamDone,
      );
      _emitProgress();
    } catch (error, stackTrace) {
      _isRecording = false;
      await _cancelSubscriptionIgnoringErrors();
      _streamDone = null;
      _encoder?.dispose();
      _encoder = null;
      _resetSession();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _handlePcm(Uint8List bytes) {
    if (!_isRecording || bytes.isEmpty || _captureError != null) return;
    try {
      final chunk = VoicePcmChunk(bytes: bytes, sampleRate: 48000, channels: 2);
      for (final frame in _framer.add(chunk)) {
        _packets.add(Uint8List.fromList(_encoder!.encode(frame)));
        _frameCount++;
        _sampleWaveform(frame);
      }
      _emitProgress();
    } catch (error) {
      _handleCaptureError(error);
    }
  }

  void _sampleWaveform(Int16List frame) {
    for (final sample in frame) {
      final normalized = sample.abs() / 32768;
      if (normalized > _peak) _peak = normalized;
    }
    _peakFrameCount++;
    if (_peakFrameCount == _framesPerWaveformSample) _flushPeak();
  }

  void _flushPeak() {
    _waveformPeaks.add(math.sqrt(_peak.clamp(0, 1)));
    _peakFrameCount = 0;
    _peak = 0;
  }

  void _emitProgress() {
    if (_progress.isClosed) return;
    _progress.add(
      VoiceMessageRecordingProgress(
        duration: Duration(milliseconds: _frameCount * 20),
        samples: _downsample(_waveformPeaks, _maxWaveformSamples),
      ),
    );
  }

  void _handleCaptureError(Object error) {
    if (_captureError != null) return;
    _captureError = error;
    if (!_progress.isClosed) _progress.addError(error);
    unawaited(_stopCaptureAfterError());
  }

  Future<void> _stopCaptureAfterError() async {
    try {
      await _capture.stop();
    } on Object {
      // The original stream error remains authoritative.
    } finally {
      _handleStreamDone();
    }
  }

  void _handleStreamDone() {
    final done = _streamDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<PendingVoiceMessage> stop() async {
    if (!_isRecording) throw StateError('No voice message is recording');
    final closeFailure = await _closeCapture(_capture.stop);
    if (_captureError case final error?) {
      _finishSession();
      throw error;
    }
    if (closeFailure case (final error, final stackTrace)) {
      _finishSession();
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (_peakFrameCount > 0) _flushPeak();
    if (_packets.isEmpty) {
      _finishSession();
      throw StateError('Voice message is empty');
    }

    try {
      final bytes = OggOpusMuxer().encode(_packets);
      final directory = await _directoryProvider();
      await directory.create(recursive: true);
      final timestamp = _clock().toUtc().microsecondsSinceEpoch.toRadixString(
        36,
      );
      final name = 'flucord-voice-$timestamp-${_fileSequence++}.ogg';
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
      _ownedPaths.add(file.path);
      final waveformBytes = _waveformBytes(_waveformPeaks);
      return PendingVoiceMessage(
        name: name,
        path: file.path,
        size: bytes.length,
        durationSecs: _frameCount / 50,
        waveform: base64Encode(waveformBytes),
      );
    } finally {
      _finishSession();
    }
  }

  @override
  Future<void> cancel() async {
    if (!_isRecording) return;
    final closeFailure = await _closeCapture(_capture.cancel);
    _finishSession();
    if (closeFailure case (final error, final stackTrace)) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<(Object, StackTrace)?> _closeCapture(
    Future<void> Function() close,
  ) async {
    (Object, StackTrace)? failure;
    try {
      await close();
      await _streamDone?.future;
    } catch (error, stackTrace) {
      failure = (error, stackTrace);
    } finally {
      _isRecording = false;
      try {
        await _subscription?.cancel();
      } catch (error, stackTrace) {
        failure ??= (error, stackTrace);
      }
      _subscription = null;
    }
    return failure;
  }

  Future<void> _cancelSubscriptionIgnoringErrors() async {
    try {
      await _subscription?.cancel();
    } on Object {
      // Preserve the original start failure.
    }
    _subscription = null;
  }

  @override
  Future<void> delete(PendingVoiceMessage message) async {
    if (!_ownedPaths.remove(message.path)) return;
    final file = File(message.path);
    if (await file.exists()) await file.delete();
  }

  void _resetSession() {
    _packets.clear();
    _waveformPeaks.clear();
    _framer.reset();
    _captureError = null;
    _frameCount = 0;
    _peakFrameCount = 0;
    _peak = 0;
  }

  void _finishSession() {
    _encoder?.dispose();
    _encoder = null;
    _streamDone = null;
    _resetSession();
  }

  static List<double> _downsample(List<double> values, int maximum) {
    if (values.length <= maximum) return List.unmodifiable(values);
    return List.generate(maximum, (index) {
      final start = index * values.length ~/ maximum;
      final end = (index + 1) * values.length ~/ maximum;
      return values.sublist(start, math.max(start + 1, end)).reduce(math.max);
    }, growable: false);
  }

  static Uint8List _waveformBytes(List<double> values) => Uint8List.fromList(
    _downsample(values, _maxWaveformSamples)
        .map((value) => math.max(1, (value.clamp(0, 1) * 255).round()))
        .toList(growable: false),
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_isRecording) await cancel();
    await _capture.dispose();
    for (final path in _ownedPaths.toList(growable: false)) {
      final file = File(path);
      if (await file.exists()) await file.delete();
      _ownedPaths.remove(path);
    }
    await _progress.close();
  }
}
