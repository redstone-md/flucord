import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/voice_call.dart';
import 'voice_controller.dart';

/// Drives calls in DMs and group DMs.
///
/// The two halves a call needs already exist and are deliberately not merged
/// here: [VoiceController] owns the media session — microphone, uplink,
/// participant grid — and [DirectCallService] owns the call record and the ring
/// routes. This controller is only the order they happen in, which is the part
/// the UI cannot be trusted to get right: ringing before joining leaves the
/// caller outside the call they placed, and declining without stopping the ring
/// leaves the phone going on the other end.
final class DirectCallController extends ChangeNotifier {
  DirectCallController({
    required this._serviceProvider,
    required VoiceController voiceController,
  }) : _voice = voiceController {
    _voice.addListener(_onVoiceChanged);
  }

  final DirectCallServiceProvider _serviceProvider;
  final VoiceController _voice;
  StreamSubscription<VoiceCallEvent>? _subscription;
  DirectCallService? _service;
  IncomingCall? _incomingCall;
  String? _lastActiveCallChannelId;
  final Set<String> _outgoingRings = <String>{};

  /// Channels whose ring we have actually seen on the wire.
  ///
  /// The CALL_CREATE that answers our own join arrives before the server has
  /// processed the ring, so it reports nobody ringing. Treating that as "the
  /// ring is over" cleared the flag immediately: the caller never saw
  /// "Ringing…", and hanging up posted no stop-ringing because there was
  /// apparently nothing to retract. A ring is only over once we have seen it
  /// present and then gone.
  final Set<String> _ringsSeen = <String>{};
  Object? _error;
  bool _isBusy = false;
  bool _disposed = false;

  /// Whether the active transport can place calls at all. A bot or offline
  /// session cannot, and the call affordances stay hidden rather than failing.
  bool get supportsCalls => _service != null;
  IncomingCall? get incomingCall => _incomingCall;
  Object? get error => _error;
  bool get isBusy => _isBusy;

  /// The channel whose call the local user is currently sitting in.
  String? get activeCallChannelId =>
      _voice.isCallSession ? _voice.connectedChannelId : null;

  DirectCall? callFor(String channelId) => _service?.callFor(channelId);

  /// Whether the local user has a ring out on [channelId] that nobody has
  /// answered yet.
  bool isRinging(String channelId) => _outgoingRings.contains(channelId);

  /// Rebinds after the session is swapped. Cheap and idempotent, so the app can
  /// call it on every transport change without tracking which one it was.
  void reconcileService() {
    final service = _serviceProvider();
    if (identical(service, _service)) return;
    unawaited(_subscription?.cancel());
    _service = service;
    _incomingCall = service?.incomingCall;
    _outgoingRings.clear();
    _ringsSeen.clear();
    _subscription = service?.callEvents.listen(_onCallEvent);
    _notify();
  }

  /// Subscribes to a private channel's call so its state is known before the
  /// user does anything. Discord pushes nothing for an unsubscribed channel.
  void watchChannel(String channelId) => _service?.watchChannel(channelId);

  /// Places a call: pre-flight, join, then ring.
  ///
  /// The pre-flight comes first because a DM with someone who is not a friend
  /// answers "not ringable", and joining a channel nobody will be told about
  /// would strand the caller alone in a silent room.
  Future<void> placeCall(String channelId) => _run(() async {
    final service = _service;
    if (service == null) return;
    if (!await service.isRingable(channelId)) {
      _error = StateError('This conversation cannot be called');
      return;
    }
    await _voice.connectToCall(channelId: channelId);
    _outgoingRings.add(channelId);
    await service.ring(channelId);
  });

  /// Walks into a call that is already running.
  ///
  /// Nobody is rung: the people in the call are already there, and the ones who
  /// declined said no once. Only [placeCall] starts a call from silence.
  Future<void> joinOngoingCall(String channelId) =>
      _run(() => _voice.connectToCall(channelId: channelId));

  /// Answers the ring by walking into the call.
  ///
  /// No `stop-ringing` is posted: R08 closes the incoming surface when the user
  /// joins the channel, and the server retracts the ring itself. Posting one
  /// would also stop the ring for everyone else in a group DM.
  Future<void> acceptIncomingCall() => _run(() async {
    final call = _incomingCall;
    if (call == null) return;
    _incomingCall = null;
    await _voice.connectToCall(channelId: call.channelId);
  });

  /// Declines by posting `stop-ringing` with no recipients, which is how the
  /// desktop client tells the server this one person said no.
  Future<void> declineIncomingCall() => _run(() async {
    final call = _incomingCall;
    final service = _service;
    if (call == null || service == null) return;
    _incomingCall = null;
    await service.stopRinging(call.channelId);
  });

  /// Leaves the call. Any ring the local user still has out is retracted by
  /// [_onVoiceChanged], which sees every departure rather than only this one.
  Future<void> hangUp() => _run(() async {
    if (activeCallChannelId == null) return;
    await _voice.disconnect();
  });

  void _onCallEvent(VoiceCallEvent event) {
    switch (event) {
      case IncomingCallChangedEvent():
        _incomingCall = event.call;
      case DirectCallEndedEvent():
        _outgoingRings.remove(event.channelId);
        _ringsSeen.remove(event.channelId);
        if (_incomingCall?.channelId == event.channelId) _incomingCall = null;
      case DirectCallUpdatedEvent():
        final channelId = event.call.channelId;
        if (event.call.ringing.isNotEmpty) {
          _ringsSeen.add(channelId);
        } else if (_ringsSeen.remove(channelId)) {
          // Seen ringing, now not: answered or timed out either way, so it is
          // no longer ours to cancel.
          _outgoingRings.remove(channelId);
        }
    }
    _notify();
  }

  /// The active call is read off the voice controller, so a hang-up or a join
  /// has to reach anything listening here or the call surface would not move.
  ///
  /// Only that one fact is forwarded. The voice controller notifies on every
  /// device enumeration and busy flip, and it does so synchronously from the
  /// room's `initState` — which lands mid-build for anything that hosts the
  /// room, and marking an ancestor dirty during its own build is an error. The
  /// channel cannot change during that window, so filtering on it is both the
  /// correct signal and the one that is safe to relay.
  void _onVoiceChanged() {
    final active = activeCallChannelId;
    final previous = _lastActiveCallChannelId;
    if (active == previous) return;
    _lastActiveCallChannelId = active;
    // Leaving a call the local user placed has to retract the ring, and the
    // room's own hang-up button goes straight to the voice controller without
    // passing through [hangUp] — so the departure, not the button, is what this
    // hangs off. Otherwise the other end keeps ringing an empty call.
    _ringsSeen.remove(previous);
    if (previous != null && _outgoingRings.remove(previous)) {
      unawaited(_service?.stopRinging(previous));
    }
    _notify();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_isBusy) return;
    _isBusy = true;
    _error = null;
    _notify();
    try {
      await action();
    } catch (error) {
      _error = error;
    } finally {
      _isBusy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _voice.removeListener(_onVoiceChanged);
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
