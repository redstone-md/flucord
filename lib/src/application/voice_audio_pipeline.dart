import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/voice_audio.dart';
import '../domain/voice_media.dart';
import '../domain/voice_processing.dart';
import 'voice_activity_gate.dart';
import 'voice_audio_receiver.dart';
import 'voice_pcm_framer.dart';

/// Microphone PCM in, Opus frames out; remote Opus in, PCM out.
///
/// Noise suppression sits between the framer and the encoder: the 20 ms
/// frames the encoder wants are whole hops of the model, so the filter adds no
/// buffering of its own. Opening the suppressor loads a model and takes the
/// better part of a second, so it happens off the frame path when the switch
/// goes on; frames pass through as captured until it is ready, and a
/// suppressor that fails to open or run turns the switch off and reports why.
///
/// Only speech goes out. A frame is sent while the [VoiceActivityGate] hears
/// the cleaned microphone above the room's noise floor, and for the gate's
/// hangover after it last did; then the uplink finishes speaking, which is
/// what tells the room this participant went quiet. A client that sent every
/// frame was heard as speaking without pause by everybody else.
final class VoiceAudioPipeline {
  VoiceAudioPipeline({
    required VoiceMediaService mediaService,
    required VoiceOpusCodecFactory codecFactory,
    Future<VoiceNoiseSuppressor> Function()? noiseSuppressorFactory,
  }) : _encoder = codecFactory.createEncoder(),
       _receiver = VoiceAudioReceiver(decoderFactory: codecFactory),
       _noiseSuppressorFactory = noiseSuppressorFactory {
    _microphoneSubscription = mediaService.microphonePcm.listen(
      _handleMicrophonePcm,
      onError: _emitError,
    );
    _receiverErrorSubscription = _receiver.errors.listen(_emitError);
  }

  /// How many silent frames it takes to push the model's lookahead and window
  /// (29 ms measured) out of it: the tail of a word that was still inside
  /// when the microphone went quiet.
  static const int _flushFrames = 2;

  /// How many quiet frames the uplink stays open after the last loud one.
  static const int hangoverFrames = VoiceActivityGate.defaultHangoverFrames;

  final VoiceOpusEncoder _encoder;
  final VoiceAudioReceiver _receiver;
  final VoicePcmFramer _framer = VoicePcmFramer();
  final Future<VoiceNoiseSuppressor> Function()? _noiseSuppressorFactory;
  final StreamController<Object> _errors = StreamController.broadcast();
  late final StreamSubscription<VoicePcmChunk> _microphoneSubscription;
  late final StreamSubscription<Object> _receiverErrorSubscription;
  VoiceAudioTransport? _transport;
  VoiceNoiseSuppressor? _noiseSuppressor;
  Future<void>? _noiseSuppressorOpening;
  bool _noiseSuppression = false;
  bool _enabled = false;
  bool _disposed = false;
  final StreamController<bool> _speaking = StreamController.broadcast();
  final VoiceActivityGate _gate = VoiceActivityGate();
  bool _isSpeaking = false;

  Stream<VoiceRemotePcmFrame> get remotePcm => _receiver.remotePcm;
  Stream<Object> get errors => _errors.stream;
  bool get isEnabled => _enabled;

  /// Whether this account's microphone is being sent: true when speech opens
  /// the uplink, false when the hangover runs out or the uplink is disabled.
  Stream<bool> get speaking => _speaking.stream;
  bool get isSpeaking => _isSpeaking;

  /// The level the microphone has to reach to be sent, in dB relative to
  /// full scale, as the gate has it now.
  double get inputThresholdDbfs => _gate.threshold;

  /// Whether this build has a suppressor to switch on at all.
  bool get isNoiseSuppressionAvailable => _noiseSuppressorFactory != null;

  /// Whether frames are, or will be once the model has loaded, cleaned.
  /// Falls back to off when the suppressor fails, so a surface reading this
  /// shows what is happening rather than what was asked for.
  bool get isNoiseSuppressionEnabled => _noiseSuppression;

  /// Switches the filter. Completes when the suppressor is open, or at once
  /// when it already is or the switch went off.
  Future<void> setNoiseSuppression(bool enabled) async {
    final factory = _noiseSuppressorFactory;
    if (factory == null || _disposed) return;
    _noiseSuppression = enabled;
    // Cleaned and raw frames have different floors.
    _gate.reset();
    if (!enabled || _noiseSuppressor != null) return;
    if (_noiseSuppressorOpening case final opening?) return opening;
    final opening = _noiseSuppressorOpening = _openNoiseSuppressor(factory);
    try {
      await opening;
    } finally {
      _noiseSuppressorOpening = null;
    }
  }

  Future<void> _openNoiseSuppressor(
    Future<VoiceNoiseSuppressor> Function() factory,
  ) async {
    try {
      final suppressor = await factory();
      // Switched off again, or torn down, while the model was loading.
      if (_disposed || !_noiseSuppression) {
        suppressor.dispose();
        return;
      }
      _noiseSuppressor = suppressor;
    } on Object catch (error) {
      _noiseSuppression = false;
      _emitError(error);
    }
  }

  Future<void> bindTransport(VoiceAudioTransport? transport) async {
    if (identical(_transport, transport)) return;
    await setEnabled(false);
    _transport = transport;
    await _receiver.bind(transport?.remoteAudio);
  }

  Future<void> setEnabled(bool enabled) async {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    _framer.reset();
    _gate.reset();
    if (!enabled) {
      _flushNoiseSuppressor();
      _setSpeaking(false);
      await _transport?.finishSpeaking();
    }
  }

  void _handleMicrophonePcm(VoicePcmChunk chunk) {
    final transport = _transport;
    if (!_enabled || transport == null || _disposed) return;
    try {
      for (final frame in _framer.add(chunk)) {
        _suppressNoise(frame);
        final speech = _gate.accept(_rmsDbfs(frame));
        if (speech) {
          _setSpeaking(true);
          transport.sendOpusFrame(_encoder.encode(frame));
        } else if (_isSpeaking) {
          _setSpeaking(false);
          unawaited(_finishSpeaking(transport));
        }
      }
    } catch (error) {
      _emitError(error);
    }
  }

  /// Ends the burst; a transport that refuses is reported like any other
  /// frame-path failure rather than thrown out of an unawaited future.
  Future<void> _finishSpeaking(VoiceAudioTransport transport) async {
    try {
      await transport.finishSpeaking();
    } on Object catch (error) {
      _emitError(error);
    }
  }

  void _setSpeaking(bool value) {
    if (_isSpeaking == value) return;
    _isSpeaking = value;
    if (!_speaking.isClosed) _speaking.add(value);
  }

  /// The frame's loudness in dB relative to full scale; silence is -infinity.
  static double _rmsDbfs(Int16List frame) {
    var energy = 0.0;
    for (final sample in frame) {
      energy += sample * sample;
    }
    final rms = math.sqrt(energy / frame.length) / 32768;
    return 20 * math.log(rms) / math.ln10;
  }

  /// Cleans [frame] in place while a suppressor is open and switched on.
  ///
  /// A suppressor that throws is dropped and the switch turned off: the frame
  /// goes out as captured, the failure is reported once, and switching on
  /// again opens a fresh one.
  void _suppressNoise(Int16List frame) {
    final suppressor = _noiseSuppressor;
    if (!_noiseSuppression || suppressor == null) return;
    try {
      suppressor.process(frame, channels: _framer.channels);
    } on Object catch (error) {
      _noiseSuppression = false;
      _noiseSuppressor = null;
      suppressor.dispose();
      _emitError(error);
    }
  }

  /// Sends the sound still inside the model when the uplink goes quiet.
  ///
  /// The model runs a window and a lookahead behind its input, so the last
  /// 29 ms of a word have not come out yet when push to talk is released.
  /// Silence pushed through brings them out, and leaves the model holding
  /// silence rather than that tail for the next press. Only while frames are
  /// actually being sent: a filter that is still loading has nothing inside.
  void _flushNoiseSuppressor() {
    final transport = _transport;
    // Only mid-burst: a closed gate has already pushed silence through the
    // model, and a frame sent now would open a burst just to end it.
    if (transport == null ||
        _noiseSuppressor == null ||
        !_noiseSuppression ||
        !_isSpeaking) {
      return;
    }
    try {
      for (var i = 0; i < _flushFrames; i++) {
        final silence = Int16List(_framer.samplesPerFrame);
        _suppressNoise(silence);
        transport.sendOpusFrame(_encoder.encode(silence));
      }
    } on Object catch (error) {
      _emitError(error);
    }
  }

  void _emitError(Object error) {
    if (!_errors.isClosed) _errors.add(error);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await setEnabled(false);
    _disposed = true;
    await _microphoneSubscription.cancel();
    await _receiverErrorSubscription.cancel();
    await _receiver.dispose();
    _encoder.dispose();
    _noiseSuppressor?.dispose();
    _noiseSuppressor = null;
    await _speaking.close();
    await _errors.close();
  }
}
