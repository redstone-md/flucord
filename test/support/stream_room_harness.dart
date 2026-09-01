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
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'pane_harness.dart';

import 'fake_video_encoder.dart';

/// A room with streams in it: the pane the app builds, over controllers that
/// record what was asked for.
///
/// The fakes live here rather than in the test that first needed them, because
/// every stream-control test starts from the same room.
final class StreamRoomHarness {
  StreamRoomHarness({
    required this.channel,
    // Who else is in the room. Somebody streaming by default, which is the
    // case every stream control exists for.
    this.seats = const [StreamRoomSeat('friend-1', isStreaming: true)],
  }) {
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
      decoderFactory: StreamRoomDecoder.new,
      ownKeyProvider: () => goLive.streamKey,
    );
    goLive = GoLiveController(
      repositoryProvider: () => repository,
      capture: VideoCaptureHub(encoder: FakeVideoEncoder(cameras: const [])),
    )..reconcile();
    composition = AppComposition(AppBootstrap.demo());
    composition.workspace
      ..reconcile(streamRoomWorkspace)
      ..selectChannel(channel.id);
    signaling.seated = {
      channel.id: [
        for (final seat in seats)
          VoiceParticipantStateEvent(
            userId: seat.userId,
            guildId: channel.guildId,
            channelId: channel.id,
            selfMuted: false,
            selfDeafened: false,
            serverMuted: false,
            serverDeafened: false,
            isStreaming: seat.isStreaming,
            isVideoEnabled: false,
          ),
      ],
    };
  }

  final ConversationChannel channel;
  final List<StreamRoomSeat> seats;
  final StreamRoomSignaling signaling = StreamRoomSignaling();
  final StreamRoomCallService callService = StreamRoomCallService();
  final StreamRoomStreamRepository repository = StreamRoomStreamRepository();
  late final VoiceController voice;
  late final DirectCallController calls;
  late final StreamViewerController viewer;
  late final GoLiveController goLive;
  late final AppComposition composition;

  /// Walks into the room, which is where the grid and its stream controls
  /// live. Left to a test that wants the unjoined preview instead.
  Future<void> joinRoom() => channel.isDirectMessage
      ? voice.connectToCall(channelId: channel.id)
      : voice.connect(guildId: channel.spaceId, channelId: channel.id);

  Widget pane() => MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: paneHarness(
        composition,
        streamRoomWorkspace,
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

/// Pumps the pane the app builds for [channel]'s room, joined by default.
Future<StreamRoomHarness> pumpStreamRoom(
  WidgetTester tester,
  ConversationChannel channel, {
  List<StreamRoomSeat> seats = const [
    StreamRoomSeat('friend-1', isStreaming: true),
  ],
  bool join = true,
}) async {
  final harness = StreamRoomHarness(channel: channel, seats: seats);
  addTearDown(harness.dispose);
  addTearDown(() => expect(tester.takeException(), isNull));
  if (join) await harness.joinRoom();
  await tester.pumpWidget(harness.pane());
  await tester.pumpAndSettle();
  return harness;
}

/// Somebody in the room, and whether they are sending a stream.
final class StreamRoomSeat {
  const StreamRoomSeat(this.userId, {this.isStreaming = false});

  final String userId;
  final bool isStreaming;
}

/// The DM call the tests walk into: a room without a guild.
const streamRoomCall = ConversationChannel(
  id: 'dm-1',
  spaceId: CommunitySpace.directMessagesId,
  name: 'Jack',
  topic: 'Direct message with Jack',
  kind: ChannelKind.text,
  recipientId: 'friend-1',
);

/// The server voice room the tests walk into: the same room, with a guild.
const streamRoomVoiceChannel = ConversationChannel(
  id: 'voice-1',
  spaceId: 'guild-1',
  name: 'General',
  topic: '',
  kind: ChannelKind.voice,
);

final streamRoomWorkspace = ChatWorkspace(
  spaces: [
    CommunitySpace.directMessages(),
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'F',
      colorValue: 0xff4c9b72,
    ),
  ],
  channels: [streamRoomCall, streamRoomVoiceChannel],
  members: [
    Member(
      id: 'me',
      displayName: 'Me',
      initials: 'ME',
      role: 'Operator',
      presence: Presence.online,
      colorValue: 0xff4c9b72,
    ),
    Member(
      id: 'friend-1',
      displayName: 'Jack',
      initials: 'JK',
      role: 'Operator',
      presence: Presence.online,
      colorValue: 0xff4c9b72,
    ),
    Member(
      id: 'friend-2',
      displayName: 'Mira',
      initials: 'MI',
      role: 'Member',
      presence: Presence.online,
      colorValue: 0xff9b4c72,
    ),
  ],
  messages: [],
  currentMemberId: 'me',
);

final class StreamRoomSignaling implements VoiceSignalingService {
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

final class StreamRoomCallService implements DirectCallService {
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

final class StreamRoomStreamRepository implements GoLiveRepository {
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

final class StreamRoomDecoder implements VideoDecoderService {
  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();

  @override
  bool get isSupported => true;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  @override
  Stream<int> get droppedAccessUnits => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> submit(List<int> accessUnit, {Duration? timestamp}) async {}

  @override
  Future<void> stop() async {}
}
