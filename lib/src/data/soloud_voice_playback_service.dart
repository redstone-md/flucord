import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import '../app_log.dart';
import '../domain/voice_audio.dart';
import '../domain/voice_media.dart';

final class SoLoudVoicePlaybackService implements VoiceAudioPlaybackService {
  static const int _sampleRate = 48000;
  static const int _channels = 2;

  /// How much sound a source holds before it plays, and refills to after it
  /// ran dry: the jitter one frame may arrive late by without a hole in the
  /// speech. A voice call stops sending between phrases, so every phrase
  /// starts from an empty buffer; the log showed holes of 40 to 180 ms in
  /// the frames after each one, each of them a crackle.
  static const double _bufferingSeconds = 0.1;

  /// Resolved on first use, not on construction: touching the singleton loads
  /// the native library, and a service that is only ever asked to stay quiet
  /// — a build with no audio module, a test — should not need it present.
  late final SoLoud _player = SoLoud.instance;
  final Map<String, _PlayingSource> _sources = {};
  bool _initialized = false;
  bool _enabled = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _player.init(
      sampleRate: _sampleRate,
      bufferSize: 960,
      channels: Channels.stereo,
      lowLatency: true,
    );
    _initialized = true;
  }

  @override
  Future<List<VoiceDevice>> enumerateOutputDevices() async {
    final devices = _player.listPlaybackDevices().toList(growable: false)
      ..sort((left, right) {
        if (left.isDefault == right.isDefault) {
          return left.name.compareTo(right.name);
        }
        return left.isDefault ? -1 : 1;
      });
    return [
      for (final device in devices)
        VoiceDevice(
          id: device.id.toString(),
          label: device.name,
          kind: VoiceDeviceKind.audioOutput,
        ),
    ];
  }

  @override
  Future<void> selectOutput(String deviceId) async {
    _requireInitialized();
    final id = int.tryParse(deviceId);
    final device = id == null
        ? null
        : _player
              .listPlaybackDevices()
              .where((item) => item.id == id)
              .firstOrNull;
    if (device == null) {
      throw StateError('Selected audio output is no longer available');
    }
    _player.changeDevice(newDevice: device);
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    // Turning off something that was never turned on is not a failure. The
    // room disables playback on every bind, long before a device has been
    // opened, and throwing there surfaced "voice playback is not initialized"
    // as though the call had a problem.
    if (!_initialized && !enabled) return;
    _requireInitialized();
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) await _disposeSources();
  }

  @override
  void addPcmFrame(VoiceRemotePcmFrame frame) {
    if (!_enabled || frame.samples.isEmpty) return;
    if (frame.samples.length % _channels != 0) {
      throw StateError('Remote PCM frame is not stereo aligned');
    }
    final playing = _sources.putIfAbsent(
      frame.sourceId,
      () => _createSource(frame.sourceId),
    );
    // Read before the frame goes in, so the primer sees the slack the frame
    // found rather than the slack it made.
    final consumed = _player.getStreamTimeConsumed(playing.source);
    try {
      _player.addAudioDataStream(playing.source, _asBytes(frame.samples));
    } on SoLoudPcmBufferFullCppException {
      _replace(frame.sourceId, playing);
      return;
    } on SoLoudStreamEndedAlreadyCppException {
      _replace(frame.sourceId, playing);
      return;
    }
    // SoLoud only refills once, when the source is new. A source that ran
    // dry later plays silence and picks the next frame up with no slack at
    // all, so the refill is done from here from then on.
    final pause = playing.primer.feed(
      Duration(
        microseconds:
            frame.samples.length ~/
            _channels *
            Duration.microsecondsPerSecond ~/
            _sampleRate,
      ),
      consumed,
    );
    if (pause != playing.paused) {
      playing.paused = pause;
      _player.setPause(playing.handle, pause);
    }
  }

  /// A stream whose buffer filled is finished for good: SoLoud marks it ended
  /// and refuses every byte after. The buffer fills when nothing consumes it
  /// (the device stopped) or when a backlog is poured in at once, and either
  /// way the sound in it is late already. The source is thrown away with it,
  /// and the next frame opens a fresh one; the failure is not reported, since
  /// the room could do nothing with it but show it on every frame.
  void _replace(String sourceId, _PlayingSource playing) {
    if (identical(_sources[sourceId], playing)) _sources.remove(sourceId);
    unawaited(_player.disposeSource(playing.source));
  }

  @override
  Future<void> removeSource(String sourceId) async {
    final playing = _sources.remove(sourceId);
    if (playing != null) await _player.disposeSource(playing.source);
  }

  _PlayingSource _createSource(String sourceId) {
    final source = _player.setBufferStream(
      maxBufferSizeDuration: const Duration(seconds: 5),
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: _bufferingSeconds,
      sampleRate: _sampleRate,
      channels: Channels.stereo,
      format: BufferType.s16le,
      // An underrun is the playback side of a crackle: the voice pauses
      // until [_bufferingSeconds] of sound is queued again. Logged so a gap
      // heard in the room can be matched against the frames that fed it.
      onBuffering: (isBuffering, handle, time) => AppLog.warning(
        'voice.playback',
        '$sourceId ${isBuffering ? 'underrun, buffering' : 'playing again'} '
            'at ${time.toStringAsFixed(2)}s',
      ),
    );
    return _PlayingSource(source, _player.play(source));
  }

  Uint8List _asBytes(Int16List samples) => Uint8List.view(
    samples.buffer,
    samples.offsetInBytes,
    samples.lengthInBytes,
  );

  Future<void> _disposeSources() async {
    final playing = _sources.values.toList(growable: false);
    _sources.clear();
    for (final each in playing) {
      await _player.disposeSource(each.source);
    }
  }

  void _requireInitialized() {
    if (!_initialized) throw StateError('Voice playback is not initialized');
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    await setEnabled(false);
    _player.deinit();
    _initialized = false;
  }
}

/// One participant's sound: the stream it is fed into, the voice playing it,
/// and the refill that keeps a late frame from being a hole.
final class _PlayingSource {
  _PlayingSource(this.source, this.handle);

  final AudioSource source;
  final SoundHandle handle;
  final PlaybackPrimer primer = PlaybackPrimer(
    need: Duration(
      milliseconds: (SoLoudVoicePlaybackService._bufferingSeconds * 1000)
          .round(),
    ),
  );
  bool paused = false;
}

/// Decides when a source is held back to refill.
///
/// A source is fed in real time and drained in real time, so whatever slack
/// it starts a phrase with is all the jitter it can absorb for the whole
/// phrase. Having run dry, it is paused until [need] of sound is queued
/// again, then let go: the phrase starts [need] late and keeps that much
/// slack. Whole microseconds, so that five 20 ms frames make exactly 100 ms.
final class PlaybackPrimer {
  PlaybackPrimer({required this.need});

  final Duration need;
  Duration _fed = Duration.zero;
  bool _priming = false;

  /// Whether the source should be paused after a frame of [frame] is added,
  /// given it had [consumed] of what was fed so far.
  bool feed(Duration frame, Duration consumed) {
    if (!_priming && _fed <= consumed) _priming = true;
    _fed += frame;
    if (_priming && _fed - consumed >= need) _priming = false;
    return _priming;
  }
}
