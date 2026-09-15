import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../app_log.dart';
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
/// The inference itself runs where the model lives, off the UI isolate, and
/// the uplink chains each frame's work behind the last one: frames leave in
/// the order the microphone produced them, and one that arrives while the
/// chain is still long is dropped rather than delayed (a live microphone
/// cannot afford a queue).
///
/// Echo cancellation and gain control sit at the same place, ahead of the
/// noise filter: they belong to the machine's own audio layer, which sees
/// what the speakers are playing while the microphone hears it, and the
/// filter would rather clean a microphone that is already free of the room
/// coming back through the speakers. One open enhancer serves both switches,
/// and turning both off closes it.
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
    Future<VoiceMicrophoneEnhancer> Function({
      required bool echoCancellation,
      required bool automaticGainControl,
    })?
    microphoneEnhancerFactory,
  }) : _encoder = codecFactory.createEncoder(),
       _receiver = VoiceAudioReceiver(decoderFactory: codecFactory),
       _noiseSuppressorFactory = noiseSuppressorFactory,
       _microphoneEnhancerFactory = microphoneEnhancerFactory {
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

  /// How many frames may wait for their turn on the uplink. Inference that
  /// keeps up never fills this; one that falls behind is shedding frames
  /// rather than adding latency to a live microphone. Five is 100 ms, twice
  /// what the model's own lookahead and window ask of it.
  static const int _uplinkBacklogLimit = 5;

  final VoiceOpusEncoder _encoder;
  final VoiceAudioReceiver _receiver;
  final VoicePcmFramer _framer = VoicePcmFramer();
  final Future<VoiceNoiseSuppressor> Function()? _noiseSuppressorFactory;

  /// Opens the machine's echo and gain processing, with the settings as they
  /// were asked for; null on a build without one.
  final Future<VoiceMicrophoneEnhancer> Function({
    required bool echoCancellation,
    required bool automaticGainControl,
  })?
  _microphoneEnhancerFactory;

  final StreamController<Object> _errors = StreamController.broadcast();
  late final StreamSubscription<VoicePcmChunk> _microphoneSubscription;
  late final StreamSubscription<Object> _receiverErrorSubscription;
  VoiceAudioTransport? _transport;
  VoiceNoiseSuppressor? _noiseSuppressor;
  Future<void>? _noiseSuppressorOpening;
  bool _noiseSuppression = false;
  VoiceMicrophoneEnhancer? _microphoneEnhancer;
  Future<void>? _microphoneEnhancerOpening;
  bool _echoCancellation = false;
  bool _automaticGainControl = false;

  /// The uplink's work, one frame at a time, in microphone order.
  Future<void> _uplink = Future<void>.value();
  int _uplinkBacklog = 0;
  int _uplinkDropped = 0;

  bool _enabled = false;
  bool _disposed = false;
  final StreamController<bool> _speaking = StreamController.broadcast();
  final VoiceActivityGate _gate = VoiceActivityGate();
  bool _isSpeaking = false;

  /// Whether the level is learned from the room (null) or chosen by hand.
  double? get inputSensitivity => _gate.isAutomatic ? null : _gate.threshold;

  /// Whether this build has the machine's echo and gain processing at all.
  bool get isMicrophoneEnhancementAvailable =>
      _microphoneEnhancerFactory != null;

  /// Whether the microphone's echo is being removed.
  ///
  /// Read from what the pipeline holds rather than what was asked for: an
  /// enhancer that fails to open turns both switches off with it.
  bool get isEchoCancellationEnabled => _echoCancellation;

  /// Whether the microphone's level is being kept steady.
  bool get isAutomaticGainControlEnabled => _automaticGainControl;

  /// Sets the level the microphone has to reach to be sent, or returns to
  /// the automatic gate with null.
  void setInputThreshold(double? dbfs) => _gate.setManualThreshold(dbfs);

  /// Switches the machine's echo and gain processing. Completes when the
  /// enhancer is open, or at once when neither is wanted or it already is.
  ///
  /// Both settings ride one enhancer: the machine's echo and gain stages
  /// share a device and a clock, so one open path serves both switches and
  /// reopening for each would cost the full setup twice. Turning both off
  /// closes it.
  Future<void> setMicrophoneEnhancement({
    required bool echoCancellation,
    required bool automaticGainControl,
  }) async {
    final factory = _microphoneEnhancerFactory;
    if (factory == null || _disposed) return;
    final wanted = echoCancellation || automaticGainControl;
    _echoCancellation = wanted && echoCancellation;
    _automaticGainControl = wanted && automaticGainControl;
    // Enhanced and raw frames have different floors.
    _gate.reset();
    if (!wanted) {
      // Both switches off: the open path closes. A path that stayed open
      // would keep a loopback of the render endpoint and the machine's
      // voice stages running for a microphone nobody asked to enhance.
      _microphoneEnhancer?.dispose();
      _microphoneEnhancer = null;
      return;
    }
    if (_microphoneEnhancer != null) return;
    if (_microphoneEnhancerOpening case final opening?) return opening;
    final opening = _microphoneEnhancerOpening = _openMicrophoneEnhancer(
      factory,
      echoCancellation: echoCancellation,
      automaticGainControl: automaticGainControl,
    );
    try {
      await opening;
    } finally {
      _microphoneEnhancerOpening = null;
    }
  }

  Future<void> _openMicrophoneEnhancer(
    Future<VoiceMicrophoneEnhancer> Function({
      required bool echoCancellation,
      required bool automaticGainControl,
    })
    factory, {
    required bool echoCancellation,
    required bool automaticGainControl,
  }) async {
    try {
      final enhancer = await factory(
        echoCancellation: echoCancellation,
        automaticGainControl: automaticGainControl,
      );
      // Both switched off again, or torn down, while it was opening.
      if (_disposed || (!_echoCancellation && !_automaticGainControl)) {
        enhancer.dispose();
        return;
      }
      _microphoneEnhancer = enhancer;
    } on Object catch (error) {
      _echoCancellation = false;
      _automaticGainControl = false;
      _emitError(error);
    }
  }

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
      // Frames already taken in finish first: they were captured while the
      // uplink was live, and cutting them off would clip the tail of a word.
      await _uplink;
      _uplink = Future<void>.value();
      _uplinkBacklog = 0;
      await _flushNoiseSuppressor();
      _setSpeaking(false);
      await _transport?.finishSpeaking();
    }
  }

  void _handleMicrophonePcm(VoicePcmChunk chunk) {
    final transport = _transport;
    if (!_enabled || transport == null || _disposed) return;
    for (final frame in _framer.add(chunk)) {
      if (_uplinkBacklog >= _uplinkBacklogLimit) {
        _noteDroppedFrame();
        continue;
      }
      _uplinkBacklog++;
      _uplink = _uplink.then((_) => _sendUplinkFrame(frame)).whenComplete(() {
        _uplinkBacklog--;
      });
    }
  }

  /// The uplink cost is growing faster than the microphone produces: say so,
  /// but not per frame, or the log becomes the problem being described.
  void _noteDroppedFrame() {
    _uplinkDropped++;
    if (_uplinkDropped == 1 || _uplinkDropped % 100 == 0) {
      AppLog.warning(
        'voice.uplink',
        'uplink dropped $_uplinkDropped frames: the filter cannot keep up',
      );
    }
  }

  /// One frame's whole turn: enhanced, cleaned, gated, encoded, sent. Never
  /// throws, so one bad frame cannot break the chain behind it.
  ///
  /// The enhance and clean steps only await when there is real work: an
  /// awaited call that does nothing still costs a turn of the event loop
  /// per frame, and a microphone that arrives faster than the empty turns
  /// drain would be dropped for no reason.
  Future<void> _sendUplinkFrame(Int16List frame) async {
    final transport = _transport;
    if (_disposed || transport == null) return;
    try {
      final enhancement = _enhancement(frame);
      if (enhancement != null) await enhancement;
      final cleaning = _suppression(frame);
      if (cleaning != null) await cleaning;
      final speech = _gate.accept(_rmsDbfs(frame));
      if (speech) {
        _setSpeaking(true);
        transport.sendOpusFrame(_encoder.encode(frame));
      } else if (_isSpeaking) {
        _setSpeaking(false);
        unawaited(_finishSpeaking(transport));
      }
    } on Object catch (error) {
      _emitError(error);
    }
  }

  /// Throws away one participant's decoder: they left the room, and their
  /// decoder is native memory that otherwise outlives them by the whole call.
  void forgetDecoder(String userId) => _receiver.forgetDecoder(userId);

  /// Takes a forgotten user back, now that the room has them again: their
  /// frames decode instead of being dropped.
  void allowDecoder(String userId) => _receiver.allowDecoder(userId);

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

  /// The frame's loudness in dB relative to full scale; silence is
  /// -infinity.
  static double _rmsDbfs(Int16List frame) {
    var energy = 0.0;
    for (final sample in frame) {
      energy += sample * sample;
    }
    final rms = math.sqrt(energy / frame.length) / 32768;
    return 20 * math.log(rms) / math.ln10;
  }

  /// Enhances [frame] while an enhancer is open and either switch is on,
  /// or answers null when there is nothing to do.
  ///
  /// An enhancer that throws is dropped and both switches turned off: the
  /// frame goes out as captured, the failure is reported once, and
  /// switching on again opens a fresh one.
  Future<void>? _enhancement(Int16List frame) {
    final enhancer = _microphoneEnhancer;
    if (enhancer == null || (!_echoCancellation && !_automaticGainControl)) {
      return null;
    }
    return () async {
      try {
        await enhancer.process(frame, channels: _framer.channels);
      } on Object catch (error) {
        _echoCancellation = false;
        _automaticGainControl = false;
        _microphoneEnhancer = null;
        enhancer.dispose();
        _emitError(error);
      }
    }();
  }

  /// Cleans [frame] while a suppressor is open and switched on, or answers
  /// null when there is nothing to do.
  ///
  /// A suppressor that throws is dropped and the switch turned off: the
  /// frame goes out as captured, the failure is reported once, and
  /// switching on again opens a fresh one.
  Future<void>? _suppression(Int16List frame) {
    final suppressor = _noiseSuppressor;
    if (!_noiseSuppression || suppressor == null) return null;
    return () async {
      try {
        await suppressor.process(frame, channels: _framer.channels);
      } on Object catch (error) {
        _noiseSuppression = false;
        _noiseSuppressor = null;
        suppressor.dispose();
        _emitError(error);
      }
    }();
  }

  /// Sends the sound still inside the model when the uplink goes quiet.
  ///
  /// The model runs a window and a lookahead behind its input, so the last
  /// 29 ms of a word have not come out yet when push to talk is released.
  /// Silence pushed through brings them out, and leaves the model holding
  /// silence rather than that tail for the next press. Only while frames are
  /// actually being sent: a filter that is still loading has nothing inside.
  Future<void> _flushNoiseSuppressor() async {
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
        final enhancement = _enhancement(silence);
        if (enhancement != null) await enhancement;
        final cleaning = _suppression(silence);
        if (cleaning != null) await cleaning;
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
    _microphoneEnhancer?.dispose();
    _microphoneEnhancer = null;
    await _speaking.close();
    await _errors.close();
  }
}
