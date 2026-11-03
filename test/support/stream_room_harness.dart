import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/app_bootstrap.dart';
import 'package:flucord/src/app_composition.dart';
import 'package:flucord/src/application/direct_call_controller.dart';
import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/application/go_live_self_preview.dart';
import 'package:flucord/src/application/room_focus.dart';
import 'package:flucord/src/application/self_video_controller.dart';
import 'package:flucord/src/application/stream_router.dart';
import 'package:flucord/src/application/stream_viewer_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/application/voice_room_coordination.dart';
import 'package:flucord/src/data/discord/discord_go_live_service.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_stream_rtc_service.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_voice_socket_factory.dart';
import 'package:flucord/src/data/soloud_voice_playback_service.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/domain/video_decoder.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_call.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'pane_harness.dart';

import 'fake_stream_client.dart';
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
    // Whether the sender's own picture can be decoded: off is the tile
    // showing why not.
    this.selfPreviewOpens = true,
  }) {
    voice = VoiceController(
      media,
      signalingServiceProvider: () => signaling,
      callServiceProvider: () => callService,
      playbackService: SoLoudVoicePlaybackService(player: audio),
      streamAudio: receivedAudio.stream,
    );
    calls = DirectCallController(
      serviceProvider: () => callService,
      voiceController: voice,
    )..reconcileService();
    viewer = StreamViewerController(
      repositoryProvider: () => repository,
      decoderFactory: () {
        final decoder = StreamRoomDecoder(failStart: viewerDecoderFails);
        viewerDecoders.add(decoder);
        return decoder;
      },
      onWatchStopped: (key) => unawaited(streamRtc.stop(key)),
    );
    streamRtc = DiscordStreamRtcService(
      repositoryProvider: () => repository,
      identityProvider: () => (sessionId: 'session-1', userId: 'me'),
      socketFactoryProvider: () => _StreamRoomSockets(streamClients),
      isWatched: viewer.isOpen,
    )..reconcile();
    router = StreamRouter(opened: streamRtc.opened, viewer: viewer);
    final capture = VideoCaptureHub(encoder: encoder);
    camera = SelfVideoController(
      capture: capture,
      transportProvider: () => cameraTransport,
      sinkProvider: () => cameraTransport.send,
      isVoiceReady: () => voice.connectionStatus == VoiceConnectionStatus.ready,
      announceSelfVideo: voice.setCameraAnnounced,
    );
    goLive = GoLiveController(
      repositoryProvider: () => repository,
      capture: capture,
      selfPreview: GoLiveSelfPreview(
        decoderFactory: () => selfPreviewDecoder = StreamRoomDecoder(
          failStart: !selfPreviewOpens,
        ),
      ),
    )..reconcile();
    composition = AppComposition(AppBootstrap.demo());
    coordination = VoiceRoomCoordination(
      voice: voice,
      remoteCameras: composition.remoteCameras,
      overlay: composition.voiceOverlay,
      streamerMode: composition.streamerMode,
      goLive: goLive,
      streamViewer: viewer,
      selfVideo: camera,
      focus: focus,
    );
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

  /// Whether the sender's own picture can be decoded.
  final bool selfPreviewOpens;

  /// The decoder the running share's preview was opened on.
  late StreamRoomDecoder selfPreviewDecoder;

  /// Whether the next decoder the viewer makes refuses to open.
  bool viewerDecoderFails = false;

  /// Every decoder the viewer made, oldest first. One is made just to ask
  /// whether the build can decode, and is never opened.
  final List<StreamRoomDecoder> viewerDecoders = [];

  /// The viewer's decoders that were opened, oldest first.
  List<StreamRoomDecoder> get openedViewerDecoders => [
    for (final decoder in viewerDecoders)
      if (decoder.started > 0) decoder,
  ];
  final StreamRoomMedia media = StreamRoomMedia();

  /// The voice connection's service. A test replaces it to play a new gateway
  /// session, then asks the voice controller to refresh.
  StreamRoomSignaling signaling = StreamRoomSignaling();
  final StreamRoomCallService callService = StreamRoomCallService();
  final StreamRoomStreamRepository repository = StreamRoomStreamRepository();

  /// Each connection a watched stream was dialled on, oldest first. A test
  /// speaks for the far end through these.
  final List<FakeStreamClient> streamClients = [];

  /// The machine's one capture, shared by the share and the camera.
  final FakeVideoEncoder encoder = FakeVideoEncoder();
  final StreamRoomCameraTransport cameraTransport = StreamRoomCameraTransport();

  /// What this machine is playing: the real playback service runs over it.
  final StreamRoomAudioEngine audio = StreamRoomAudioEngine();

  /// Decoded sound reaching the room: voice under the person's id, a watched
  /// stream under its key.
  final StreamController<VoiceRemotePcmFrame> receivedAudio =
      StreamController.broadcast();
  late final VoiceController voice;
  late final DirectCallController calls;
  late final StreamViewerController viewer;
  late final DiscordStreamRtcService streamRtc;
  late final StreamRouter router;
  late final GoLiveController goLive;
  late final SelfVideoController camera;
  late final AppComposition composition;
  late final VoiceRoomCoordination coordination;

  /// Whose tile is on the stage, as the pane reads it. Not the composition's:
  /// that one follows the composition's own voice controller, which is never
  /// in this room, and would clear the focus the first time it spoke.
  final RoomFocus focus = RoomFocus();

  /// Walks into the room, which is where the grid and its stream controls
  /// live. Left to a test that wants the unjoined preview instead.
  Future<void> joinRoom() => channel.isDirectMessage
      ? voice.connectToCall(channelId: channel.id)
      : voice.connect(guildId: channel.spaceId, channelId: channel.id);

  /// What Discord sends in answer to an ask: the stream, and where to dial it.
  void answerWatch(GoLiveStreamKey key) => repository
    ..dispatch('STREAM_CREATE', {'stream_key': key.value})
    ..dispatch('STREAM_SERVER_UPDATE', {
      'stream_key': key.value,
      'endpoint': 'stream.discord.gg',
      'token': 'stream-token',
    });

  /// The pane the app builds, on [showing] when the person has moved away from
  /// the room's own channel.
  Widget pane({ConversationChannel? showing}) => MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: paneHarness(
        composition,
        streamRoomWorkspace,
        channel: showing ?? channel,
        voice: voice,
        directCall: calls,
        goLive: goLive,
        streamViewer: viewer,
        camera: camera,
        focus: focus,
      ),
    ),
  );

  void dispose() {
    coordination.dispose();
    composition.dispose();
    camera.dispose();
    goLive.dispose();
    viewer.dispose();
    calls.dispose();
    voice.dispose();
    router.dispose();
    focus.dispose();
    unawaited(streamRtc.close().then((_) => repository.close()));
    unawaited(receivedAudio.close());
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
  bool selfPreviewOpens = true,
}) async {
  final harness = StreamRoomHarness(
    channel: channel,
    seats: seats,
    selfPreviewOpens: selfPreviewOpens,
  );
  addTearDown(harness.dispose);
  addTearDown(() => expect(tester.takeException(), isNull));
  if (join) await harness.joinRoom();
  await tester.pumpWidget(harness.pane());
  await tester.pumpAndSettle();
  return harness;
}

/// Lets the news reach the room, then draws what the room became.
///
/// Closing a connection cancels subscriptions, which is real async work that a
/// fake-async test body cannot wait out, so the wait in the middle is a real
/// one.
Future<void> settleStreamRoom(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(pumpEventQueue);
  await tester.pump();
}

/// The session a stream connection reports once it is ready.
const streamRoomTransport = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 4242,
  address: '127.0.0.1',
  port: 50000,
  mode: 'aead_aes256_gcm_rtpsize',
  secretKey: <int>[],
  daveProtocolVersion: 0,
);

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

/// The machine's audio devices: whether the microphone is live, and a way to
/// keep them opening for as long as a test needs.
final class StreamRoomMedia implements VoiceMediaService {
  bool microphoneOn = false;

  /// While set, opening the devices waits on it.
  Completer<void>? hold;

  @override
  Stream<VoicePcmChunk> get microphonePcm => const Stream.empty();

  @override
  Future<void> initialize() async => hold?.future;

  @override
  Future<List<VoiceDevice>> enumerateDevices() async => const [];

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async =>
      microphoneOn = enabled;

  @override
  Future<void> startMicrophone(String? deviceId) async => microphoneOn = true;

  @override
  Future<void> stopMicrophone() async => microphoneOn = false;

  @override
  Future<void> dispose() async {}
}

/// One voice state the room sent. A null [channelId] is a leave.
typedef StreamRoomVoiceFrame = ({
  String? channelId,
  bool selfMute,
  bool selfDeaf,
  bool selfVideo,
});

final class StreamRoomSignaling implements VoiceSignalingService {
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast();

  Map<String, List<VoiceParticipantStateEvent>> seated = const {};

  /// What the voice connection says next.
  void emit(VoiceSignalingEvent event) => _events.add(event);

  /// Ends the event stream, as a service that closed does.
  Future<void> closeEvents() => _events.close();

  /// Every voice state sent, in order.
  final List<StreamRoomVoiceFrame> frames = [];

  /// While set, a join or a leave stays in flight after its frame goes out,
  /// which is how a test holds a voice action open.
  Completer<void>? hold;

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
  }) async {
    frames.add((
      channelId: channelId,
      selfMute: selfMute,
      selfDeaf: selfDeaf,
      selfVideo: selfVideo,
    ));
    await hold?.future;
  }

  @override
  Future<void> leaveVoiceChannel(String guildId) async {
    frames.add((
      channelId: null,
      selfMute: false,
      selfDeaf: false,
      selfVideo: false,
    ));
    await hold?.future;
  }
}

final class StreamRoomCallService implements DirectCallService {
  final StreamController<VoiceCallEvent> _events = StreamController.broadcast();

  /// Every voice state the call plane sent, in order.
  final List<StreamRoomVoiceFrame> frames = [];

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
  }) async => frames.add((
    channelId: channelId,
    selfMute: selfMute,
    selfDeaf: selfDeaf,
    selfVideo: selfVideo,
  ));

  @override
  Future<void> leaveCall(String channelId) async {}
}

/// Records what the room asked for, over the real fold of Discord's stream
/// dispatches, so a test sends in what Discord sends.
final class StreamRoomStreamRepository implements GoLiveRepository {
  final _StreamRoomGateway _gateway = _StreamRoomGateway();
  late final DiscordGoLiveService _service = DiscordGoLiveService(_gateway);
  final List<GoLiveStreamKey> watched = [];
  final List<GoLiveStreamKey> ended = [];
  final List<String> startedChannels = [];
  final List<String?> startedGuildIds = [];

  /// The asks and withdrawals that went out to Discord, in order, by the
  /// opcode's name and the stream's key.
  List<String> get watchFrames => _gateway.watchFrames;

  /// A raw gateway dispatch, as Discord would send it.
  void dispatch(String eventName, Map<String, Object?> data) =>
      _service.accept(eventName, data);

  Future<void> close() => _service.close();

  @override
  Map<String, GoLiveStream> get streams => _service.streams;

  @override
  Stream<GoLiveStream> get updates => _service.updates;

  @override
  Stream<GoLiveServer> get servers => _service.servers;

  /// Echoes the key the create frame asked for, so what a test reads back as
  /// ended is what the room asked to start. Hardcoding one here made the stop
  /// half of the round trip assert the fake against itself.
  @override
  Future<GoLiveStreamKey> startStream({
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) {
    startedChannels.add(channelId);
    startedGuildIds.add(guildId);
    return _service.startStream(channelId: channelId, guildId: guildId);
  }

  @override
  Future<void> watchStream(GoLiveStreamKey key) async {
    watched.add(key);
    await _service.watchStream(key);
  }

  @override
  Future<void> pingStream(GoLiveStreamKey key) async {}

  @override
  Future<void> setPaused(GoLiveStreamKey key, {required bool paused}) async {}

  @override
  Future<void> endStream(GoLiveStreamKey key) {
    ended.add(key);
    return _service.endStream(key);
  }

  @override
  Future<void> stopWatching(GoLiveStreamKey key) => _service.stopWatching(key);
}

/// The frames the repository sends. [watchFrames] is the part a watch puts on
/// the wire; what a share asks for is recorded one level up.
final class _StreamRoomGateway implements DiscordGoLiveGateway {
  final List<String> watchFrames = [];

  @override
  String? get currentUserId => 'me';

  @override
  void sendStreamCreate({
    required String type,
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) {}

  @override
  void sendStreamDelete(String streamKey) =>
      watchFrames.add('STREAM_DELETE $streamKey');

  @override
  void sendStreamWatch(String streamKey) =>
      watchFrames.add('STREAM_WATCH $streamKey');

  @override
  void sendStreamPing(String streamKey) {}

  @override
  void sendStreamSetPaused(String streamKey, {required bool paused}) {}
}

/// Dials a fake connection for each watched stream, and keeps it for the test.
final class _StreamRoomSockets implements DiscordVoiceSocketFactory {
  const _StreamRoomSockets(this._clients);

  final List<FakeStreamClient> _clients;

  @override
  int get maxDaveProtocolVersion => 0;

  @override
  DiscordVoiceClient callSocket(VoiceServerCredentials credentials) =>
      throw UnsupportedError('the stream plane dials no call sockets');

  @override
  DiscordVoiceClient streamSocket({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) {
    final client = FakeStreamClient();
    _clients.add(client);
    return client;
  }
}

/// One sound the machine is playing, at the level it is heard.
final class StreamRoomPlayingSound {
  StreamRoomPlayingSound(this.source, this.handle);

  final AudioSource source;
  final SoundHandle handle;
  double volume = 1;
}

/// The audio engine with no sound card: it keeps what is playing and how loud.
final class StreamRoomAudioEngine extends Fake implements SoLoud {
  final List<StreamRoomPlayingSound> playing = [];
  int _nextHandle = 1;

  @override
  Future<void> init({
    PlaybackDevice? device,
    bool automaticCleanup = false,
    int sampleRate = 44100,
    int bufferSize = 2048,
    Channels channels = Channels.stereo,
    bool lowLatency = true,
    AndroidAAudioAttributes androidAAudioAttributes =
        AndroidAAudioAttributes.mediaMusic,
  }) async {}

  @override
  List<PlaybackDevice> listPlaybackDevices() => const [];

  @override
  AudioSource setBufferStream({
    int? maxBufferSizeBytes,
    Duration? maxBufferSizeDuration,
    BufferingType bufferingType = BufferingType.preserved,
    double bufferingTimeNeeds = 2,
    int sampleRate = 24000,
    Channels channels = Channels.mono,
    BufferType format = BufferType.s16le,
    void Function(bool isBuffering, int handle, double time)? onBuffering,
    void Function(AudioMetadata)? onMetadata,
  }) => _StreamRoomAudioSource();

  @override
  SoundHandle play(
    AudioSource sound, {
    int busId = 0,
    double volume = 1,
    double pan = 0,
    bool paused = false,
    bool looping = false,
    Duration loopingStartAt = Duration.zero,
  }) {
    final handle = SoundHandle(_nextHandle++);
    playing.add(StreamRoomPlayingSound(sound, handle));
    return handle;
  }

  @override
  Duration getStreamTimeConsumed(AudioSource sound) => Duration.zero;

  @override
  void addAudioDataStream(AudioSource source, Uint8List audioChunk) {}

  @override
  void setPause(SoundHandle handle, bool pause) {}

  @override
  void setInaudibleBehavior(SoundHandle handle, bool mustTick, bool kill) {}

  @override
  void setVolume(SoundHandle handle, double volume) =>
      playing.firstWhere((sound) => sound.handle == handle).volume = volume;

  @override
  Future<void> disposeSource(AudioSource source) async =>
      playing.removeWhere((sound) => identical(sound.source, source));

  @override
  void deinit() => playing.clear();
}

/// A sound the engine knows by identity alone.
final class _StreamRoomAudioSource extends Fake implements AudioSource {}

/// The voice side of the camera: declares SSRCs, takes pictures.
final class StreamRoomCameraTransport implements VoiceVideoTransport {
  final List<bool> announcements = [];

  /// The audio SSRC in force at each announcement, which is what opcode 12
  /// derives the camera's numbers from.
  final List<int?> announcedSsrcs = [];

  /// Every packet handed to the wire, in order.
  final List<DiscordRtpFrame> sent = [];

  /// The SSRC this session holds. A test changes it to play a new session, and
  /// null plays the gap before the voice `READY`.
  @override
  int? audioSsrc = 40;

  int send(DiscordRtpFrame frame) {
    sent.add(frame);
    return frame.payload.length;
  }

  @override
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  }) {
    announcements.add(enabled);
    announcedSsrcs.add(audioSsrc);
    return true;
  }
}

final class StreamRoomDecoder implements VideoTextureDecoder {
  StreamRoomDecoder({this.failStart = false});

  final bool failStart;
  int started = 0;
  int stopped = 0;

  /// The timestamp of each picture handed to this decoder, in the order it
  /// was handed over.
  final List<Duration?> submitted = [];

  @override
  bool get isSupported => true;

  @override
  Stream<VideoTexture> get textures => const Stream.empty();

  @override
  Stream<int> get droppedAccessUnits => const Stream.empty();

  @override
  Future<void> start() async {
    if (failStart) throw StateError('no decoder');
    started++;
  }

  @override
  Future<void> submit(List<int> accessUnit, {Duration? timestamp}) async =>
      submitted.add(timestamp);

  @override
  Future<void> stop() async => stopped++;
}
