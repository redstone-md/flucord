part of 'voice_controller.dart';

/// The input meter's half of the controller: the microphone's level for the
/// voice settings, read with or without a call.
///
/// The meter shares the call's microphone rather than opening one of its own:
/// the machine has one capture of it, and the call must not lose it because
/// a settings page closed. So the microphone has two holders, the call and
/// the meter, and stops only when neither wants it.
///
/// The level is the captured one, before the call's own echo, noise and gain
/// stages: those run only while the uplink is live.
extension VoiceControllerInputLevel on VoiceController {
  void _startMeter() {
    final framer = VoicePcmFramer();
    _meterSubscription = _mediaService.microphonePcm
        .expand(framer.add)
        .map(VoiceActivityGate.levelOf)
        .listen(_inputLevels.add, onError: _inputLevels.addError);
    _queueMeterAction(() async {
      if (_meterSubscription == null || isConnected) return;
      await initialize();
      await _openMeterMicrophone();
    });
  }

  void _stopMeter() {
    unawaited(_meterSubscription?.cancel());
    _meterSubscription = null;
    _queueMeterAction(() async {
      if (_meterSubscription != null || isConnected) return;
      await _mediaService.stopMicrophone();
    });
  }

  /// Queues [action] behind the joins and leaves, a turn later: a meter
  /// starts and stops while widgets build and unmount, and the queue tells
  /// its listeners it is busy, which must wait until that is over.
  void _queueMeterAction(Future<void> Function() action) =>
      scheduleMicrotask(() => unawaited(_enqueue(action)));

  /// Opens the microphone for the meter alone, and hands the meter the reason
  /// when it will not open.
  Future<void> _openMeterMicrophone() async {
    await _openMicrophone();
    if (_microphoneError case final error?) _inputLevels.addError(error);
  }

  /// A call ended: its microphone stops, unless the meter still reads it.
  /// The call's mute ends with the call, so the meter hears the room again.
  Future<void> _releaseCallMicrophone() async {
    if (_meterSubscription == null) {
      await _mediaService.stopMicrophone();
    } else {
      await _mediaService.setMicrophoneEnabled(true);
    }
  }

  /// A muted microphone sends nothing, so the meter would hold its last
  /// reading; it drops to silence instead.
  void _meterHearsSilence() {
    if (_inputLevels.hasListener) _inputLevels.add(double.negativeInfinity);
  }
}
