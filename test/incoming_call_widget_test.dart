import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/direct_call_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/presentation/widgets/incoming_call_overlay.dart';
import 'package:flucord/src/presentation/widgets/voice_participant_grid.dart';
import 'package:flucord/src/presentation/widgets/voice_room_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

const _accept = ValueKey('incoming-call-accept');
const _decline = ValueKey('incoming-call-decline');

void main() {
  testWidgets('names the caller and answers the ring', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('incoming-call-card')), findsNothing);

    harness.ring();
    await tester.pumpAndSettle();

    expect(find.text('Jack'), findsOneWidget);
    expect(find.text('Incoming call · Jack'), findsOneWidget);

    await tester.tap(find.byKey(_accept));
    await tester.pumpAndSettle();

    expect(harness.service.log, ['join:dm-1']);
    expect(find.byKey(const ValueKey('incoming-call-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('declines the ring', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app());
    harness.ring();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_decline));
    await tester.pumpAndSettle();

    expect(harness.service.log, ['stop:dm-1']);
    expect(find.byKey(const ValueKey('incoming-call-card')), findsNothing);
  });

  testWidgets('falls back when the caller and channel are unknown', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app());
    harness.ring(channelId: 'unlisted-dm', callerId: 'stranger');
    await tester.pumpAndSettle();

    expect(find.text('Someone'), findsOneWidget);
    expect(find.text('Incoming call'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card survives a compact window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app());
    harness.ring();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('incoming-call-card')), findsOneWidget);
    expect(find.byKey(_accept), findsOneWidget);
    expect(find.byKey(_decline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the room shows the people in it while nobody is watched', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = _Harness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: VoiceRoomView(
            guildId: null,
            spaceId: 'direct-messages',
            channelId: 'dm-1',
            channelName: 'Jack',
            controller: harness.voice,
            members: const [_jack],
            currentMemberId: 'me',
            // A viewer widget that draws nothing while idle. `??` cannot tell
            // it apart from one that is showing a stream, so the participant
            // grid was never reached and the room looked empty.
            streamViewer: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-channel-join')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('voice-participants-empty')), findsWidgets);
  });

  testWidgets('the room joins a call when there is no guild', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = _Harness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: VoiceRoomView(
            guildId: null,
            spaceId: 'direct-messages',
            channelId: 'dm-1',
            channelName: 'Jack',
            controller: harness.voice,
            members: const [_jack],
            currentMemberId: 'me',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Opening a call channel does not dial it, the same way opening a voice
    // channel does not join one.
    expect(harness.service.log, isEmpty);
    await tester.tap(find.byKey(const ValueKey('voice-channel-join')));
    await tester.pumpAndSettle();

    // The same room, the same grid: a call reuses them rather than forking.
    expect(harness.service.log, ['join:dm-1']);
    expect(harness.voice.isCallSession, isTrue);
    expect(harness.voice.connectedGuildId, isNull);
    expect(find.byKey(const ValueKey('voice-mute')), findsOneWidget);
    expect(find.byType(VoiceParticipantGrid), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _jack = Member(
  id: 'friend-1',
  displayName: 'Jack',
  initials: 'J',
  role: 'Direct message',
  presence: Presence.online,
  colorValue: 0xff5865f2,
);

final class _Harness {
  _Harness() {
    voice = VoiceController(
      _SilentMediaService(),
      callServiceProvider: () => service,
    );
    controller = DirectCallController(
      serviceProvider: () => service,
      voiceController: voice,
    );
    controller.reconcileService();
  }

  final _FakeCallService service = _FakeCallService();
  late final VoiceController voice;
  late final DirectCallController controller;

  void ring({String channelId = 'dm-1', String callerId = 'friend-1'}) =>
      service.emitIncoming(
        IncomingCall(channelId: channelId, callerId: callerId),
      );

  Widget app() => MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Stack(
        children: [
          const SizedBox.expand(),
          IncomingCallOverlay(controller: controller, workspace: _workspace),
        ],
      ),
    ),
  );

  void dispose() {
    controller.dispose();
    voice.dispose();
    unawaited(service.close());
  }
}

final ChatWorkspace _workspace = ChatWorkspace(
  spaces: const [CommunitySpace.directMessages()],
  channels: const [
    ConversationChannel(
      id: 'dm-1',
      spaceId: 'direct-messages',
      name: 'Jack',
      topic: 'Direct message with Jack',
      kind: ChannelKind.text,
      recipientId: 'friend-1',
    ),
  ],
  members: const [_jack],
  messages: const [],
  currentMemberId: 'me',
);

final class _FakeCallService implements DirectCallService {
  final StreamController<VoiceCallEvent> _events = StreamController.broadcast();
  final List<String> log = [];
  IncomingCall? _incomingCall;

  @override
  Stream<VoiceCallEvent> get callEvents => _events.stream;

  @override
  IncomingCall? get incomingCall => _incomingCall;

  void emitIncoming(IncomingCall? call) {
    _incomingCall = call;
    _events.add(IncomingCallChangedEvent(call));
  }

  @override
  DirectCall? callFor(String channelId) => null;

  @override
  void watchChannel(String channelId) {}

  @override
  Future<bool> isRingable(String channelId) async => true;

  @override
  Future<void> ring(String channelId, {List<String>? recipients}) async =>
      log.add('ring:$channelId');

  @override
  Future<void> stopRinging(
    String channelId, {
    List<String>? recipients,
  }) async => log.add('stop:$channelId');

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
