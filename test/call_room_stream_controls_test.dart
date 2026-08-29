import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/app_composition.dart';
import 'package:flucord/src/application/direct_call_controller.dart';
import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/application/stream_viewer_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/data/noop_voice_media_service.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/go_live_viewer.dart';
import 'package:flucord/src/presentation/widgets/voice_participant_grid.dart';
import 'package:flucord/src/presentation/widgets/voice_room_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/pane_harness.dart';

/// A call is a room without a guild, and these are the controls a server voice
/// room already had. The one thing that could go wrong is the key: a stream is
/// addressed by room and sender, so a room that passed the DM pseudo-space as
/// a guild would ask Discord for a server no account is in.
void main() {
  testWidgets('a call room offers the stream somebody else is sending', (
    tester,
  ) async {
    await _pumpRoom(tester, _dm);

    expect(find.byType(VoiceRoomView), findsOneWidget);
    expect(find.byKey(const ValueKey('go-live-toggle')), findsOneWidget);
    // The icon alone was all a call used to show.
    expect(find.byKey(const ValueKey('voice-watch-friend-1')), findsOneWidget);
  });

  testWidgets('opening a stream in a call asks for a call stream key', (
    tester,
  ) async {
    final harness = await _pumpRoom(tester, _dm);

    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
    await tester.pumpAndSettle();

    expect(harness.repository.watched, [
      const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'friend-1'),
    ]);
  });

  testWidgets('this account sends a stream in a call, and stops', (
    tester,
  ) async {
    final harness = await _pumpRoom(tester, _dm);

    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    // No guild in the create frame: the room is a call, and Discord answers a
    // guild-flavoured create for a call with a stream nobody can open.
    expect(harness.repository.startedGuildIds, [null]);
    expect(harness.repository.startedChannels, ['dm-1']);

    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    expect(harness.repository.ended, [
      const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'me'),
    ]);
  });

  testWidgets('the stream takes the stage, and the grid comes back', (
    tester,
  ) async {
    final harness = await _pumpRoom(tester, _dm);

    await tester.runAsync(
      () => harness.viewer.attach(
        const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'friend-1'),
        packets: const Stream.empty(),
      ),
    );
    // Not settled: the stage keeps a spinner up until the first picture
    // arrives, and this stream is deliberately silent.
    await tester.pump();

    expect(find.byType(GoLiveViewer), findsOneWidget);
    expect(find.byType(VoiceParticipantGrid), findsNothing);

    // Cancelling the packet subscription is real async work, which a
    // fake-async test body cannot wait out.
    await tester.runAsync(harness.viewer.stop);
    await tester.pump();

    expect(find.byType(GoLiveViewer), findsNothing);
    expect(find.byType(VoiceParticipantGrid), findsOneWidget);
  });

  testWidgets('a server voice room still asks for a guild stream key', (
    tester,
  ) async {
    final harness = await _pumpRoom(tester, _guildVoice);

    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
    await tester.pumpAndSettle();

    expect(harness.repository.watched, [
      const GoLiveStreamKey.guild(
        guildId: 'guild-1',
        channelId: 'voice-1',
        userId: 'friend-1',
      ),
    ]);
  });

  testWidgets('a server voice room joins as a guild room, not as a call', (
    tester,
  ) async {
    final harness = await _pumpRoom(tester, _guildVoice, join: false);

    await tester.tap(find.byKey(const ValueKey('voice-channel-join')));
    await tester.pumpAndSettle();

    // The join is the half the stream key cannot cover: the key comes off the
    // channel, so it would still be right on a room that had joined as a
    // call, and only the request Discord gets would be wrong.
    expect(harness.voice.connectedGuildId, 'guild-1');
    expect(harness.voice.isCallSession, isFalse);
  });
}

/// Joins [channel]'s room and pumps the pane the app builds.
///
/// Every test here starts from the same place: a room with somebody in it who
/// is sending a stream.
Future<_Harness> _pumpRoom(
  WidgetTester tester,
  ConversationChannel channel, {
  // Unjoined, the room is a preview with a join button, which is the only
  // surface that reaches the connect the room's guild id steers.
  bool join = true,
}) async {
  final harness = _Harness(channel: channel);
  addTearDown(harness.dispose);
  addTearDown(() => expect(tester.takeException(), isNull));
  if (join) await harness.joinRoom();
  await tester.pumpWidget(harness.pane());
  await tester.pumpAndSettle();
  return harness;
}

const _dm = ConversationChannel(
  id: 'dm-1',
  spaceId: CommunitySpace.directMessagesId,
  name: 'Jack',
  topic: 'Direct message with Jack',
  kind: ChannelKind.text,
  recipientId: 'friend-1',
);

const _guildVoice = ConversationChannel(
  id: 'voice-1',
  spaceId: 'guild-1',
  name: 'General',
  topic: '',
  kind: ChannelKind.voice,
);

final _workspace = ChatWorkspace(
  spaces: [
    CommunitySpace.directMessages(),
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'F',
      colorValue: 0xff4c9b72,
    ),
  ],
  channels: [_dm, _guildVoice],
  members: [
    Member(
      id: 'friend-1',
      displayName: 'Jack',
      initials: 'JK',
      role: 'Operator',
      presence: Presence.online,
      colorValue: 0xff4c9b72,
    ),
  ],
  messages: [],
  currentMemberId: 'me',
);

/// The four controllers a room's stream controls read, swapped for fakes that
/// record what was asked for. Everything else comes from a demo composition.
final class _Harness {
  _Harness({required this.channel}) {
    voice = VoiceController(
      const NoopVoiceMediaService(),
      signalingServiceProvider: () => signaling,
      callServiceProvider: () => callService,
    );
    calls = DirectCallController(
      serviceProvider: () => callService,
      voiceController: voice,
    )..reconcileService();
    viewer = StreamViewerController(
      repositoryProvider: () => repository,
      decoder: _FakeDecoder(),
    );
    goLive = GoLiveController(
      repositoryProvider: () => repository,
      capture: VideoCaptureHub(encoder: _FakeEncoder()),
    )..reconcile();
    composition = AppComposition(AppBootstrap.demo());
    composition.workspace
      ..reconcile(_workspace)
      ..selectChannel(channel.id);
    signaling.seated = {
      channel.id: [
        VoiceParticipantStateEvent(
          userId: 'friend-1',
          guildId: channel.guildId,
          channelId: channel.id,
          selfMuted: false,
          selfDeafened: false,
          serverMuted: false,
          serverDeafened: false,
          isStreaming: true,
          isVideoEnabled: false,
        ),
      ],
    };
  }

  final ConversationChannel channel;
  final _FakeSignaling signaling = _FakeSignaling();
  final _FakeCallService callService = _FakeCallService();
  final _FakeStreamRepository repository = _FakeStreamRepository();
  late final VoiceController voice;
  late final DirectCallController calls;
  late final StreamViewerController viewer;
  late final GoLiveController goLive;
  late final AppComposition composition;

  Future<void> joinRoom() => channel.isDirectMessage
      ? voice.connectToCall(channelId: channel.id)
      : voice.connect(guildId: channel.spaceId, channelId: channel.id);

  Widget pane() => MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: paneHarness(
        composition,
        _workspace,
        channel: channel,
        voice: voice,
        directCall: calls,
        goLive: goLive,
        streamViewer: viewer,
      ),
    ),
  );

  void dispose() {
    composition.dispose();
    goLive.dispose();
    viewer.dispose();
    calls.dispose();
    voice.dispose();
  }
}

final class _FakeSignaling implements VoiceSignalingService {
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();

  Map<String, List<VoiceParticipantStateEvent>> seated = const {};

  @override
  Stream<VoiceSignalingEvent> get voiceEvents => _events.stream;

  @override
  VoiceConnectionStatus currentStatus = VoiceConnectionStatus.ready;

  @override
  VoiceTransportSession? currentSession;

  @override
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel => seated;

  @override
  Stream<void> get seatedChanges => const Stream.empty();

  @override
  Future<void> joinVoiceChannel({
    required String guildId,
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) async {}

  @override
  Future<void> leaveVoiceChannel(String guildId) async {}
}

final class _FakeCallService implements DirectCallService {
  final StreamController<VoiceCallEvent> _events = StreamController.broadcast();

  @override
  Stream<VoiceCallEvent> get callEvents => _events.stream;

  @override
  IncomingCall? get incomingCall => null;

  @override
  DirectCall? callFor(String channelId) => null;

  @override
  void watchChannel(String channelId) {}

  @override
  Future<bool> isRingable(String channelId) async => true;

  @override
  Future<void> ring(String channelId, {List<String>? recipients}) async {}

  @override
  Future<void> stopRinging(
    String channelId, {
    List<String>? recipients,
  }) async {}

  @override
  Future<void> joinCall({
    required String channelId,
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
  }) async {}

  @override
  Future<void> leaveCall(String channelId) async {}
}

final class _FakeStreamRepository implements GoLiveRepository {
  final List<GoLiveStreamKey> watched = [];
  final List<GoLiveStreamKey> ended = [];
  final List<String> startedChannels = [];
  final List<String?> startedGuildIds = [];

  @override
  Map<String, GoLiveStream> get streams => const {};

  @override
  Stream<GoLiveStream> get updates => const Stream.empty();

  @override
  Stream<GoLiveServer> get servers => const Stream.empty();

  /// Echoes the key the create frame asked for, so what a test reads back as
  /// ended is what the room asked to start. Hardcoding one here made the stop
  /// half of the round trip assert the fake against itself.
  @override
  Future<GoLiveStreamKey> startStream({
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) async {
    startedChannels.add(channelId);
    startedGuildIds.add(guildId);
    return guildId == null
        ? GoLiveStreamKey.call(channelId: channelId, userId: 'me')
        : GoLiveStreamKey.guild(
            guildId: guildId,
            channelId: channelId,
            userId: 'me',
          );
  }

  @override
  Future<void> watchStream(GoLiveStreamKey key) async => watched.add(key);

  @override
  Future<void> pingStream(GoLiveStreamKey key) async {}

  @override
  Future<void> setPaused(GoLiveStreamKey key, {required bool paused}) async {}

  @override
  Future<void> endStream(GoLiveStreamKey key) async => ended.add(key);
}

final class _FakeDecoder implements VideoDecoderService {
  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();

  @override
  bool get isSupported => true;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> submit(List<int> accessUnit, {Duration? timestamp}) async {}

  @override
  Future<void> stop() async {}
}

final class _FakeEncoder implements VideoEncoderService {
  @override
  VideoEncoderDiagnostics? get diagnostics => null;

  @override
  bool get isSupported => true;

  @override
  List<String> get cameraNames => const [];

  @override
  int get displayCount => 1;

  @override
  Stream<EncodedVideoFrame> get frames => const Stream.empty();

  @override
  Future<void> start(VideoEncoderSettings requested) async {}

  @override
  Future<void> requestKeyframe() async {}

  @override
  Future<void> setPaused({required bool paused}) async {}

  @override
  Future<void> stop() async {}
}
