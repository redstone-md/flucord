import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/direct_call_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/client_sounds.dart';
import 'package:flucord/src/domain/voice_media.dart';

void main() {
  test('a transport with no call plane offers nothing', () {
    final harness = _Harness(withService: false);
    addTearDown(harness.dispose);

    harness.controller.reconcileService();

    expect(harness.controller.supportsCalls, isFalse);
    expect(harness.controller.activeCallChannelId, isNull);
    harness.controller.watchChannel('dm-1');
  });

  test('places a call by joining first and ringing second', () async {
    final harness = _Harness()..service!.ringable = true;
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    await harness.controller.placeCall('dm-1');

    expect(harness.service!.log, ['ringable:dm-1', 'join:dm-1', 'ring:dm-1']);
    expect(harness.controller.activeCallChannelId, 'dm-1');
    expect(harness.controller.isRinging('dm-1'), isTrue);
    expect(harness.controller.error, isNull);
  });

  test('starts the call without ringing when nobody can be rung', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    await harness.controller.placeCall('dm-1');

    expect(harness.service!.log, ['ringable:dm-1', 'join:dm-1']);
    expect(harness.controller.activeCallChannelId, 'dm-1');
    expect(harness.controller.isRinging('dm-1'), isFalse);
    expect(harness.controller.error, isNull);
  });

  test('keeps the refusal of a caller who may not call at all', () async {
    final harness = _Harness()..service!.refuseCalls = true;
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    await harness.controller.placeCall('dm-1');

    expect(harness.service!.log, ['ringable:dm-1']);
    expect(harness.controller.activeCallChannelId, isNull);
    expect(harness.controller.error, isA<StateError>());
  });

  test('answering walks into the call without stopping the ring', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    harness.service!.emitIncoming(
      const IncomingCall(channelId: 'dm-1', callerId: 'friend-1'),
    );
    await harness.settle();
    expect(harness.controller.incomingCall?.callerId, 'friend-1');

    await harness.controller.acceptIncomingCall();

    // The server retracts the ring itself; posting stop-ringing here would also
    // silence a group DM for everyone else.
    expect(harness.service!.log, ['join:dm-1']);
    expect(harness.controller.incomingCall, isNull);
    expect(harness.controller.activeCallChannelId, 'dm-1');
  });

  test('declining stops the ring and leaves the call alone', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    harness.service!.emitIncoming(
      const IncomingCall(channelId: 'dm-1', callerId: 'friend-1'),
    );
    await harness.settle();
    await harness.controller.declineIncomingCall();

    expect(harness.service!.log, ['stop:dm-1:all']);
    expect(harness.controller.incomingCall, isNull);
    expect(harness.controller.activeCallChannelId, isNull);
  });

  test('accepting or declining nothing is a no-op', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    await harness.controller.acceptIncomingCall();
    await harness.controller.declineIncomingCall();
    await harness.controller.hangUp();

    expect(harness.service!.log, isEmpty);
  });

  test('hanging up on a call we placed cancels our own ring', () async {
    final harness = _Harness()..service!.ringable = true;
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    await harness.controller.placeCall('dm-1');
    harness.service!.log.clear();
    await harness.controller.hangUp();

    // Leaving the media session and retracting the ring are two separate
    // things: without the second, the other end keeps ringing an empty call.
    expect(harness.service!.log, ['leave:dm-1', 'stop:dm-1:all']);
    expect(harness.controller.activeCallChannelId, isNull);
    expect(harness.controller.activeCallChannelId, isNull);
    expect(harness.controller.isRinging('dm-1'), isFalse);
  });

  test('leaving the room from its own toolbar retracts the ring', () async {
    final harness = _Harness()..service!.ringable = true;
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    await harness.controller.placeCall('dm-1');
    harness.service!.log.clear();

    // The room's hang-up button drives the voice controller directly, never
    // this controller, so the ring has to be retracted off the departure.
    await harness.voice.disconnect();

    expect(harness.service!.log, ['leave:dm-1', 'stop:dm-1:all']);
    expect(harness.controller.isRinging('dm-1'), isFalse);
  });

  test(
    'a ring the server reports answered stops being ours to cancel',
    () async {
      final harness = _Harness()..service!.ringable = true;
      addTearDown(harness.dispose);
      harness.controller.reconcileService();

      await harness.controller.placeCall('dm-1');

      // The CALL_CREATE answering our own join arrives before the server has
      // processed the ring, so it reports nobody ringing. That is "not yet",
      // not "answered", and must not retract the ring.
      harness.service!.emit(
        const DirectCallUpdatedEvent(DirectCall(channelId: 'dm-1')),
      );
      await harness.settle();
      expect(harness.controller.isRinging('dm-1'), isTrue);

      // Now the ring is really on the wire, and then really gone.
      harness.service!.emit(
        const DirectCallUpdatedEvent(
          DirectCall(channelId: 'dm-1', ongoingRings: {'friend-1': 'me'}),
        ),
      );
      await harness.settle();
      harness.service!.emit(
        const DirectCallUpdatedEvent(DirectCall(channelId: 'dm-1')),
      );
      await harness.settle();
      expect(harness.controller.isRinging('dm-1'), isFalse);

      harness.service!.log.clear();
      await harness.controller.hangUp();
      expect(harness.service!.log, ['leave:dm-1']);
    },
  );

  test('a rejected ring surfaces as an error, not a crash', () async {
    final harness = _Harness()
      ..service!.ringable = true
      ..service!.failRings = true;
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    await harness.controller.placeCall('dm-1');

    expect(harness.controller.error, isA<StateError>());
    expect(harness.controller.isBusy, isFalse);
  });

  test('a call that ends clears the ring and the incoming surface', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    harness.service!.emitIncoming(
      const IncomingCall(channelId: 'dm-1', callerId: 'friend-1'),
    );
    harness.service!.emit(const DirectCallEndedEvent('dm-1'));
    await harness.settle();

    expect(harness.controller.incomingCall, isNull);
  });

  test('rebinding swaps the stream and drops the old session state', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.controller.reconcileService();
    harness.service!.emitIncoming(
      const IncomingCall(channelId: 'dm-1', callerId: 'friend-1'),
    );
    await harness.settle();

    // Rebinding with the identical service must not resubscribe.
    harness.controller.reconcileService();
    expect(harness.controller.incomingCall?.callerId, 'friend-1');

    final replacement = _FakeCallService();
    addTearDown(replacement.close);
    harness.service = replacement;
    harness.controller.reconcileService();

    expect(harness.controller.incomingCall, isNull);
    expect(harness.controller.supportsCalls, isTrue);
    expect(harness.controller.callFor('dm-1'), isNull);
  });

  test('reads the live call record through the service', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.controller.reconcileService();
    harness.service!.record = const DirectCall(
      channelId: 'dm-1',
      messageId: 'call-message',
    );

    expect(harness.controller.callFor('dm-1')?.isRingable, isTrue);
  });

  test('a ring loops while it is up, and stops with the surface', () async {
    final harness = _Harness();
    harness.controller.reconcileService();
    addTearDown(harness.dispose);

    harness.service!.emitIncoming(
      const IncomingCall(channelId: 'dm-1', callerId: 'friend-1'),
    );
    await harness.settle();
    // A re-announcement of the same ring does not restart it.
    harness.service!.emitIncoming(
      const IncomingCall(channelId: 'dm-1', callerId: 'friend-1'),
    );
    await harness.settle();
    harness.service!.emitIncoming(null);
    await harness.settle();

    expect(harness.sounds.log, ['loop call_ringing', 'stop']);
  });

  test('accepting stops the ring', () async {
    final harness = _Harness();
    harness.controller.reconcileService();
    addTearDown(harness.dispose);

    harness.service!.emitIncoming(
      const IncomingCall(channelId: 'dm-1', callerId: 'friend-1'),
    );
    await harness.settle();
    await harness.controller.acceptIncomingCall();

    // The join sound is the room's, not the call's.
    expect(harness.sounds.log, ['loop call_ringing', 'stop']);
  });

  test('declining stops the ring', () async {
    final harness = _Harness();
    harness.controller.reconcileService();
    addTearDown(harness.dispose);

    harness.service!.emitIncoming(
      const IncomingCall(channelId: 'dm-2', callerId: 'friend-1'),
    );
    await harness.settle();
    await harness.controller.declineIncomingCall();

    expect(harness.sounds.log, ['loop call_ringing', 'stop']);
  });

  test('the caller hears the calling tone until the ring is over', () async {
    final harness = _Harness()..service!.ringable = true;
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    await harness.controller.placeCall('dm-1');
    expect(harness.sounds.log, ['loop call_calling']);

    harness.service!.emit(
      const DirectCallUpdatedEvent(
        DirectCall(channelId: 'dm-1', ongoingRings: {'friend-1': 'me'}),
      ),
    );
    await harness.settle();
    harness.service!.emit(
      const DirectCallUpdatedEvent(DirectCall(channelId: 'dm-1')),
    );
    await harness.settle();

    expect(harness.sounds.log, ['loop call_calling', 'stop']);
  });

  test('hanging up stops the calling tone', () async {
    final harness = _Harness()..service!.ringable = true;
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    await harness.controller.placeCall('dm-1');
    await harness.controller.hangUp();

    expect(harness.sounds.log, ['loop call_calling', 'stop']);
  });

  test(
    'a machine with no playback layer still places and answers calls',
    () async {
      // The sounds are a courtesy: a session without a player answers, rings,
      // and hangs up exactly the same.
      final harness = _Harness(withSounds: false);
      addTearDown(harness.dispose);
      harness.controller.reconcileService();

      harness.service!.emitIncoming(
        const IncomingCall(channelId: 'dm-1', callerId: 'friend-1'),
      );
      await harness.settle();
      await harness.controller.acceptIncomingCall();

      expect(harness.controller.activeCallChannelId, 'dm-1');
    },
  );

  test('a rebind adopts a ring that arrived while nobody was listening', () {
    final harness = _Harness();
    harness.service!.holdIncoming = const IncomingCall(
      channelId: 'dm-1',
      callerId: 'friend-1',
    );
    harness.controller.reconcileService();
    addTearDown(harness.dispose);

    expect(harness.controller.incomingCall?.callerId, 'friend-1');
    expect(harness.sounds.log, ['loop call_ringing']);
  });

  test('one action at a time', () async {
    final harness = _Harness()..service!.ringable = true;
    addTearDown(harness.dispose);
    harness.controller.reconcileService();

    final first = harness.controller.placeCall('dm-1');
    final second = harness.controller.placeCall('dm-2');
    await Future.wait([first, second]);

    expect(
      harness.service!.log.where((entry) => entry.endsWith('dm-2')),
      isEmpty,
    );
    expect(harness.controller.isBusy, isFalse);
  });
}

final class _Harness {
  _Harness({bool withService = true, bool withSounds = true}) {
    service = withService ? _FakeCallService() : null;
    voice = VoiceController(
      _SilentMediaService(),
      callServiceProvider: () => service,
    );
    controller = DirectCallController(
      serviceProvider: () => service,
      voiceController: voice,
      sounds: withSounds ? sounds : null,
    );
  }

  _FakeCallService? service;
  late final VoiceController voice;
  late final DirectCallController controller;

  /// The ring tones the call started and stopped.
  final _RecordingSounds sounds = _RecordingSounds();

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  void dispose() {
    controller.dispose();
    voice.dispose();
    unawaited(service?.close());
  }
}

final class _RecordingSounds implements ClientSoundPlayer {
  final List<String> log = [];

  @override
  void play(ClientSound sound) => log.add('play ${sound.discordName}');

  @override
  void loop(ClientSound sound) => log.add('loop ${sound.discordName}');

  @override
  void stopLoop() => log.add('stop');
}

final class _FakeCallService implements DirectCallService {
  final StreamController<VoiceCallEvent> _events = StreamController.broadcast();
  final List<String> log = [];
  bool ringable = false;
  bool refuseCalls = false;
  bool failRings = false;
  DirectCall? record;
  IncomingCall? _incomingCall;

  /// Held as if a ring had arrived before the controller subscribed, which
  /// is what a rebind sees.
  IncomingCall? holdIncoming;

  @override
  Stream<VoiceCallEvent> get callEvents => _events.stream;

  @override
  IncomingCall? get incomingCall => holdIncoming ?? _incomingCall;

  void emit(VoiceCallEvent event) => _events.add(event);

  void emitIncoming(IncomingCall? call) {
    _incomingCall = call;
    _events.add(IncomingCallChangedEvent(call));
  }

  @override
  DirectCall? callFor(String channelId) =>
      record?.channelId == channelId ? record : null;

  @override
  void watchChannel(String channelId) => log.add('watch:$channelId');

  @override
  Future<bool> isRingable(String channelId) async {
    log.add('ringable:$channelId');
    if (refuseCalls) throw StateError('not eligible');
    return ringable;
  }

  @override
  Future<void> ring(String channelId, {List<String>? recipients}) async {
    if (failRings) throw StateError('rejected');
    log.add('ring:$channelId');
  }

  @override
  Future<void> stopRinging(
    String channelId, {
    List<String>? recipients,
  }) async => log.add('stop:$channelId:${recipients?.join(',') ?? 'all'}');

  @override
  Future<void> joinCall({
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) async => log.add('join:$channelId');

  @override
  Future<void> leaveCall(String channelId) async => log.add('leave:$channelId');

  Future<void> close() => _events.close();
}

/// A media service that does nothing, so the controller under test is the only
/// moving part.
final class _SilentMediaService implements VoiceMediaService {
  final StreamController<VoicePcmChunk> _microphone =
      StreamController.broadcast();

  @override
  Stream<VoicePcmChunk> get microphonePcm => _microphone.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<VoiceDevice>> enumerateDevices() async => const [];

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> startMicrophone(String? deviceId) async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> dispose() async {
    await _microphone.close();
  }
}
