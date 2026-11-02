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
import 'package:flucord/src/application/stream_viewer_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/application/voice_room_coordination.dart';
import 'package:flucord/src/data/discord/discord_go_live_service.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
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
      decoderFactory: StreamRoomDecoder.new,
    );
    final capture = VideoCaptureHub(encoder: encoder);
    camera = SelfVideoController(
      capture: capture,
      transportProvider: () => cameraTransport,
      sinkProvider: () => cameraTransport.send,
      isVoiceReady: () => voice.connectionStatus == VoiceConnectionStatus.ready,
      announceSelfVideo: ({required bool enabled}) async => true,
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
      focus: composition.roomFocus,
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
  final StreamRoomMedia media = StreamRoomMedia();
  final StreamRoomSignaling signaling = StreamRoomSignaling();
  final StreamRoomCallService callService = StreamRoomCallService();
  final StreamRoomStreamRepository repository = StreamRoomStreamRepository();

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
  late final GoLiveController goLive;
  late final SelfVideoController camera;
  late final AppComposition composition;
  late final VoiceRoomCoordination coordination;

  /// Whose tile is on the stage, as the pane reads it.
  RoomFocus get focus => composition.roomFocus;

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
    coordination.dispose();
    composition.dispose();
    camera.dispose();
    goLive.dispose();
    viewer.dispose();
    calls.dispose();
    voice.dispose();
    unawaited(repository.close());
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

/// Records what the room asked for, over the real fold of Discord's stream
/// dispatches, so a test sends in what Discord sends.
final class StreamRoomStreamRepository implements GoLiveRepository {
  final DiscordGoLiveService _service = DiscordGoLiveService(
    const _StreamRoomGateway(),
  );
  final List<GoLiveStreamKey> watched = [];
  final List<GoLiveStreamKey> ended = [];
  final List<String> startedChannels = [];
  final List<String?> startedGuildIds = [];

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
  Future<void> watchStream(GoLiveStreamKey key) async => watched.add(key);

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
  Future<void> stopWatching(GoLiveStreamKey key) async {}
}

/// The frames the repository sends. [StreamRoomStreamRepository] records what
/// was asked for one level up, so nothing here needs to.
final class _StreamRoomGateway implements DiscordGoLiveGateway {
  const _StreamRoomGateway();

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
  void sendStreamDelete(String streamKey) {}

  @override
  void sendStreamWatch(String streamKey) {}

  @override
  void sendStreamPing(String streamKey) {}

  @override
  void sendStreamSetPaused(String streamKey, {required bool paused}) {}
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

  @override
  int? get audioSsrc => 40;

  int send(DiscordRtpFrame frame) => frame.payload.length;

  @override
  bool announceVideo({
    required bool enabled,
    required VideoEncoderSettings settings,
  }) {
    announcements.add(enabled);
    return true;
  }
}

final class StreamRoomDecoder implements VideoDecoderService {
  StreamRoomDecoder({this.failStart = false});

  final bool failStart;
  final StreamController<DecodedVideoFrame> _frames =
      StreamController.broadcast();
  int started = 0;

  @override
  bool get isSupported => true;

  @override
  Stream<DecodedVideoFrame> get frames => _frames.stream;

  @override
  Stream<int> get droppedAccessUnits => const Stream.empty();

  @override
  Future<void> start() async {
    if (failStart) throw StateError('no decoder');
    started++;
  }

  @override
  Future<void> submit(List<int> accessUnit, {Duration? timestamp}) async {}

  @override
  Future<void> stop() async {}
}
