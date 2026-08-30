import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_call_api.dart';
import 'package:flucord/src/data/discord/discord_direct_call_service.dart';
import 'package:flucord/src/data/discord/discord_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_voice_signaling_service.dart';
import 'package:flucord/src/data/discord/discord_voice_socket_factory.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';

void main() {
  test('subscribes to a channel before anything can be learned about it', () {
    final harness = _Harness()..service.watchChannel('dm-1');
    addTearDown(harness.close);

    expect(harness.gateway.watched, ['dm-1']);
    // An empty id is not a channel; it would subscribe the session to nothing.
    harness.service.watchChannel('');
    expect(harness.gateway.watched, ['dm-1']);
  });

  test('rings straight away once the call record allows it', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    harness.dispatch('CALL_CREATE', {
      'channel_id': 'dm-1',
      'message_id': 'call-message',
    });
    await harness.settle();
    await harness.service.ring('dm-1', recipients: const ['friend-1']);

    expect(harness.api.rings.single.$1, 'dm-1');
    expect(harness.api.rings.single.$2, ['friend-1']);
    expect(harness.api.rings.single.$3, 'dm_invite');
  });

  test('holds a ring until CALL_CREATE and keeps the recipients', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    // R08: Discord rejects a ring before the call exists, so it is enqueued.
    await harness.service.ring('dm-1', recipients: const ['friend-1']);
    expect(harness.api.rings, isEmpty);

    // A record without a message id still cannot be rung.
    harness.dispatch('CALL_CREATE', {'channel_id': 'dm-1'});
    await harness.settle();
    expect(harness.api.rings, isEmpty);

    harness.dispatch('CALL_UPDATE', {
      'channel_id': 'dm-1',
      'message_id': 'call-message',
    });
    await harness.settle();

    // The intended semantics, not the renderer's off-by-sign: the recipients
    // the caller asked for survive the wait.
    expect(harness.api.rings, hasLength(1));
    expect(harness.api.rings.single.$1, 'dm-1');
    expect(harness.api.rings.single.$2, ['friend-1']);
  });

  test('a held ring with no recipients rings everybody', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    await harness.service.ring('dm-1');
    harness.dispatch('CALL_CREATE', {
      'channel_id': 'dm-1',
      'message_id': 'call-message',
    });
    await harness.settle();

    expect(harness.api.rings.single.$2, isNull);
  });

  test('a cancelled ring is not resurrected by a late CALL_CREATE', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    await harness.service.ring('dm-1');
    await harness.service.stopRinging('dm-1');
    harness.dispatch('CALL_CREATE', {
      'channel_id': 'dm-1',
      'message_id': 'call-message',
    });
    await harness.settle();

    expect(harness.api.rings, isEmpty);
    expect(harness.api.stopped, [('dm-1', null)]);
  });

  test('a ring that fails after the call exists does not break it', () async {
    final harness = _Harness()..api.failRings = true;
    addTearDown(harness.close);

    await harness.service.ring('dm-1');
    harness.dispatch('CALL_CREATE', {
      'channel_id': 'dm-1',
      'message_id': 'call-message',
    });
    await harness.settle();

    expect(harness.service.callFor('dm-1'), isNotNull);
  });

  test('stops ringing one specific recipient', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    await harness.service.stopRinging('dm-1', recipients: const ['friend-1']);

    expect(harness.api.stopped.single.$1, 'dm-1');
    expect(harness.api.stopped.single.$2, ['friend-1']);
  });

  test('a failed pre-flight means not ringable, not an outage', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    harness.api.ringable = true;
    expect(await harness.service.isRingable('dm-1'), isTrue);

    harness.api.failPreflight = true;
    expect(await harness.service.isRingable('dm-1'), isFalse);
  });

  test('reports the ring aimed at the local user and its retraction', () async {
    final harness = _Harness();
    addTearDown(harness.close);
    final events = <VoiceCallEvent>[];
    final subscription = harness.service.callEvents.listen(events.add);
    addTearDown(subscription.cancel);

    harness.service.setCurrentUserId('me');
    harness.dispatch('CALL_CREATE', {
      'channel_id': 'dm-1',
      'message_id': 'call-message',
      'ongoing_rings': {'me': 'caller-1'},
    });
    await harness.settle();

    expect(
      harness.service.incomingCall,
      const IncomingCall(channelId: 'dm-1', callerId: 'caller-1'),
    );
    expect(
      events.whereType<IncomingCallChangedEvent>().last.call?.callerId,
      'caller-1',
    );

    harness.dispatch('CALL_UPDATE', {
      'channel_id': 'dm-1',
      'message_id': 'call-message',
      'ongoing_rings': <String, Object?>{},
    });
    await harness.settle();

    expect(harness.service.incomingCall, isNull);
    expect(events.whereType<IncomingCallChangedEvent>().last.call, isNull);
  });

  test('a ring arriving before the workspace names us still lands', () async {
    final harness = _Harness();
    addTearDown(harness.close);

    harness.dispatch('CALL_CREATE', {
      'channel_id': 'dm-1',
      'ongoing_rings': {'me': 'caller-1'},
    });
    await harness.settle();
    expect(harness.service.incomingCall, isNull);

    harness.service.setCurrentUserId('me');
    expect(harness.service.incomingCall?.callerId, 'caller-1');
  });

  test(
    'joining a call subscribes to it and hands media to signalling',
    () async {
      final harness = _Harness();
      addTearDown(harness.close);
      harness.signalingUserId('me');

      await harness.service.joinCall(channelId: 'dm-1', selfMute: true);

      expect(harness.gateway.watched, ['dm-1']);
      expect(harness.gateway.callStates, [('dm-1', true, true)]);

      await harness.service.leaveCall('dm-1');
      expect(harness.gateway.callStates.last, ('dm-1', false, false));
    },
  );

  test('a closed service stops listening', () async {
    final harness = _Harness();
    await harness.service.close();
    await harness.service.close();

    harness.dispatch('CALL_CREATE', {'channel_id': 'dm-1'});
    await harness.settle();

    expect(harness.service.callFor('dm-1'), isNull);
    await harness.closeGateway();
  });
}

final class _Harness {
  _Harness() {
    signaling = DiscordVoiceSignalingService(
      mainGateway: gateway,
      socketFactory: _CallSocketFactory((credentials) => _InertVoiceClient()),
      callGateway: gateway,
    );
    service = DiscordDirectCallService(
      api: api,
      gateway: gateway,
      signaling: signaling,
      events: gateway.events,
    );
  }

  final _FakeCallGateway gateway = _FakeCallGateway();
  final _FakeCallApi api = _FakeCallApi();
  late final DiscordVoiceSignalingService signaling;
  late final DiscordDirectCallService service;

  void signalingUserId(String userId) => signaling.setCurrentUserId(userId);

  void dispatch(String name, Map<String, Object?> data) =>
      gateway.dispatch(name, data);

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    await service.close();
    await signaling.close();
    await closeGateway();
  }

  Future<void> closeGateway() => gateway.close();
}

final class _FakeCallGateway
    implements DiscordVoiceStateGateway, DiscordCallGateway {
  final StreamController<DiscordGatewayEvent> _events =
      StreamController.broadcast();
  final List<String> watched = [];
  final List<(String, bool, bool)> callStates = [];

  @override
  Stream<DiscordGatewayEvent> get events => _events.stream;

  @override
  String? get sessionId => 'session-1';

  void dispatch(String name, Map<String, Object?> data) =>
      _events.add(DiscordGatewayDispatch(name: name, data: data));

  Future<void> close() => _events.close();

  @override
  void connectToCall(String channelId) => watched.add(channelId);

  @override
  void updateCallVoiceState({
    required String channelId,
    required bool connected,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) => callStates.add((channelId, connected, selfMute));

  @override
  void updateVoiceState({
    required String guildId,
    required String? channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) => throw UnsupportedError('Guild voice is not part of this test');

  @override
  void pingVoiceServer() {}
}

final class _FakeCallApi implements DiscordCallApi {
  final List<(String, List<String>?, String)> rings = [];
  final List<(String, List<String>?)> stopped = [];
  bool ringable = false;
  bool failPreflight = false;
  bool failRings = false;

  @override
  Future<bool> isChannelRingable(String channelId) async {
    if (failPreflight) throw StateError('rejected');
    return ringable;
  }

  @override
  Future<void> ringChannel(
    String channelId, {
    List<String>? recipients,
    required String analyticsLocation,
  }) async {
    if (failRings) throw StateError('rejected');
    rings.add((channelId, recipients, analyticsLocation));
  }

  @override
  Future<void> stopRingingChannel(
    String channelId, {
    List<String>? recipients,
  }) async => stopped.add((channelId, recipients));
}

final class _InertVoiceClient implements DiscordVoiceClient {
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();

  @override
  int? get audioSsrc => null;

  @override
  Stream<VoiceSignalingEvent> get events => _events.stream;

  @override
  Stream<(String, DiscordRtpFrame)> get videoPackets =>
      const Stream<(String, DiscordRtpFrame)>.empty();

  @override
  Stream<VoiceRemoteOpusFrame> get remoteAudio =>
      const Stream<VoiceRemoteOpusFrame>.empty();

  @override
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  }) => false;

  @override
  int sendVideoFrame(DiscordRtpFrame frame) => 0;

  @override
  Uint8List encryptVideoForGroup({
    required int ssrc,
    required Uint8List frame,
  }) => frame;

  @override
  Future<void> connect() async {}

  @override
  Future<void> close() => _events.close();
}

final class _CallSocketFactory implements DiscordVoiceSocketFactory {
  @override
  int get maxDaveProtocolVersion => 0;

  _CallSocketFactory(this._build);

  final DiscordVoiceClient Function(VoiceServerCredentials credentials) _build;

  @override
  DiscordVoiceClient callSocket(VoiceServerCredentials credentials) =>
      _build(credentials);

  @override
  DiscordVoiceClient streamSocket({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) => throw UnsupportedError('the call plane dials no streams');
}
