import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/data/discord/go_live_sender.dart';
import 'package:flucord/src/domain/go_live_media.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 4242,
  address: '127.0.0.1',
  port: 50000,
  mode: 'aead_aes256_gcm_rtpsize',
  secretKey: <int>[],
  daveProtocolVersion: 0,
);

/// The same connection, resumed under a new SSRC.
const _renumbered = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 5000,
  address: '127.0.0.1',
  port: 50000,
  mode: 'aead_aes256_gcm_rtpsize',
  secretKey: <int>[],
  daveProtocolVersion: 0,
);

const _settings = VideoEncoderSettings(
  bitrate: 2500000,
  width: 1280,
  height: 720,
  framesPerSecond: 30,
);

/// One small keyframe: an SPS and an IDR slice, as the encoder produces it.
final Uint8List _keyframe = Uint8List.fromList([
  0,
  0,
  0,
  1,
  0x67,
  0x42,
  0,
  0,
  1,
  0x65,
  ...List.filled(8, 0xaa),
]);

EncodedVideoFrame _picture() => EncodedVideoFrame(
  bytes: _keyframe,
  timestamp: const Duration(milliseconds: 100),
  isKeyframe: true,
);

/// A sender over a fake connection, with what it said and was told recorded.
final class _Opened {
  _Opened({Stream<EncodedVideoFrame>? frames}) {
    sender = GoLiveWireSender(
      client: client,
      frames: frames ?? this.frames.stream,
      settings: _settings,
    );
    sender.encoderCommands.listen(commands.add);
    sender.statuses.listen(statuses.add);
    addTearDown(sender.close);
  }

  final client = _FakeClient();
  final frames = StreamController<EncodedVideoFrame>.broadcast();
  final commands = <GoLiveEncoderCommand>[];
  final statuses = <GoLiveSenderStatus>[];
  late final GoLiveWireSender sender;

  void ready([VoiceTransportSession session = _session]) =>
      client.emit(VoiceTransportReadyEvent(session));
}

void main() {
  test('dials, announces on ready with its settings, and sends', () async {
    final opened = _Opened();
    await Future<void>.delayed(Duration.zero);
    expect(opened.client.connects, 1);
    expect(opened.sender.status, GoLiveSenderStatus.dialling);
    // Nothing to send on before the connection is ready and announced.
    expect(opened.sender.takePaceLine(), isNull);
    expect(opened.client.announcements, isEmpty);

    opened.ready();
    await Future<void>.delayed(Duration.zero);

    expect(opened.statuses, [GoLiveSenderStatus.ready]);
    expect(opened.client.announcements.single.settings, _settings);
    // The encoder's first keyframe is long gone: one is asked for at once.
    expect(opened.commands, [isA<GoLiveKeyframeCommand>()]);

    opened.frames.add(_picture());
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Sent on the SSRC above the connection's, encrypted for the group once,
    // as a whole picture, before packetising.
    expect(opened.client.sentFrames, isNotEmpty);
    expect(
      opened.client.sentFrames.every((frame) => frame.header.ssrc == 4243),
      isTrue,
    );
    expect(opened.client.groupEncryptions, [4243]);
    expect(opened.sender.takePaceLine(), contains('healthy'));
  });

  test('a new SSRC on reconnect rebuilds the transport', () async {
    final opened = _Opened();
    opened.ready();
    opened.frames.add(_picture());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(opened.client.sentFrames.last.header.ssrc, 4243);

    opened.client.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.reconnecting),
    );
    opened.ready(_renumbered);
    opened.frames.add(_picture());
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Frames on the old numbering would be dropped by the server.
    expect(opened.client.sentFrames.last.header.ssrc, 5001);
    expect(opened.client.announcements, hasLength(2));
  });

  test('the stream is held while the transport is down', () async {
    final opened = _Opened(frames: const Stream<EncodedVideoFrame>.empty());
    opened.ready();
    opened.client.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.reconnecting),
    );
    await Future<void>.delayed(Duration.zero);
    expect(opened.sender.status, GoLiveSenderStatus.held);
    opened.sender.sendOpusFrame(Uint8List.fromList([1, 2, 3]));
    expect(opened.client.opus, isEmpty);

    // Discord answers a resume with RESUMED alone and never a second session
    // description, so the connection re-announcing the session it kept is the
    // only thing that lifts the hold.
    opened.ready();
    opened.sender.sendOpusFrame(Uint8List.fromList([1, 2, 3]));
    expect(opened.client.opus, hasLength(1));
    await Future<void>.delayed(Duration.zero);
    expect(opened.statuses, [
      GoLiveSenderStatus.ready,
      GoLiveSenderStatus.held,
      GoLiveSenderStatus.ready,
    ]);
  });

  test('a missed packet is resent, a lost picture asks the encoder', () async {
    final opened = _Opened();
    opened.ready();
    opened.frames.add(_picture());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sent = opened.client.sentFrames.length;

    // Answered from the sender's history, on the rtx SSRC (one above the
    // video's), not by the encoder being asked to redraw.
    opened.client.emit(
      const VoiceRetransmitRequestedEvent(ssrc: 4243, sequences: [0]),
    );
    expect(opened.client.sentFrames.length, sent + 1);
    expect(opened.client.sentFrames.last.header.ssrc, 4244);

    opened.commands.clear();
    opened.client.emit(const VoiceKeyframeRequestedEvent());
    await Future<void>.delayed(Duration.zero);
    expect(opened.commands, [isA<GoLiveKeyframeCommand>()]);
    expect(
      opened.sender.takePaceLine(),
      contains('1/1 resent, 1 keyframe req'),
    );
  });

  test('sound goes through the connection\'s own audio path once ready', () {
    final opened = _Opened(frames: const Stream<EncodedVideoFrame>.empty());

    // The capture produces sound before the endpoint answered; a frame sent
    // then is dropped rather than thrown at a transport that is not up.
    opened.sender.sendOpusFrame(Uint8List.fromList([1, 2, 3]));
    expect(opened.client.opus, isEmpty);

    opened.ready();
    opened.sender.sendOpusFrame(Uint8List.fromList([1, 2, 3]));
    expect(opened.client.opus, hasLength(1));
  });

  test(
    'loss lowers the bitrate, and a reshape of the same shape keeps it',
    () async {
      final opened = _Opened();
      opened.ready();
      await Future<void>.delayed(Duration.zero);
      opened.commands.clear();

      opened.client.emit(
        const VoiceReceiverReportEvent(
          ssrc: 4243,
          lossRatio: 0.2,
          cumulativeLost: 9,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      // Backed off by half the loss.
      expect(
        (opened.commands.single as GoLiveBitrateCommand).bitsPerSecond,
        2250000,
      );

      // A bitrate alone: Discord hears nothing, and the adapter keeps what
      // the link taught it rather than starting over at the new target.
      opened.sender.reshape(
        const VideoEncoderSettings(
          bitrate: 3000000,
          width: 1280,
          height: 720,
          framesPerSecond: 30,
        ),
      );
      expect(opened.client.announcements, hasLength(1));
      expect(opened.sender.takePaceLine(), contains('bitrate 2700k'));
    },
  );

  test('a reshape with a new shape is announced on the running connection', () {
    final opened = _Opened();
    opened.ready();
    const taller = VideoEncoderSettings(
      bitrate: 4000000,
      width: 1920,
      height: 1080,
      framesPerSecond: 60,
    );

    opened.sender.reshape(taller);

    expect(opened.client.announcements, hasLength(2));
    expect(opened.client.announcements.last.settings, taller);
  });

  test('a reshape before ready is what ready announces', () {
    final opened = _Opened();
    const taller = VideoEncoderSettings(
      bitrate: 4000000,
      width: 1920,
      height: 1080,
      framesPerSecond: 60,
    );
    opened.sender.reshape(taller);
    expect(opened.client.announcements, isEmpty);

    opened.ready();

    expect(opened.client.announcements.single.settings, taller);
  });

  test('a refused connection is reported as failed', () async {
    final opened = _Opened(frames: const Stream<EncodedVideoFrame>.empty());
    opened.client.emit(
      VoiceSignalingStatusEvent(
        VoiceConnectionStatus.failure,
        error: StateError('refused'),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(opened.sender.status, GoLiveSenderStatus.failed);
    expect(opened.statuses, [GoLiveSenderStatus.failed]);
  });

  test('closing closes the connection and says so', () async {
    final opened = _Opened(frames: const Stream<EncodedVideoFrame>.empty());

    await opened.sender.close();

    expect(opened.client.closed, isTrue);
    expect(opened.sender.status, GoLiveSenderStatus.closed);
    expect(opened.statuses, [GoLiveSenderStatus.closed]);
  });
}

final class _FakeClient implements DiscordVoiceClient, VoiceAudioTransport {
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast(sync: true);
  final List<DiscordRtpFrame> sentFrames = [];
  final List<({bool enabled, VideoEncoderSettings settings})> announcements =
      [];
  final List<int> groupEncryptions = [];
  final List<Uint8List> opus = [];
  int connects = 0;
  bool closed = false;

  void emit(VoiceSignalingEvent event) => _events.add(event);

  @override
  int? get audioSsrc => 4242;

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
  }) {
    announcements.add((enabled: enabled, settings: settings));
    return true;
  }

  @override
  int sendVideoFrame(DiscordRtpFrame frame) {
    sentFrames.add(frame);
    return frame.payload.length;
  }

  @override
  void sendMediaSinkWants({
    Map<int, int> perSsrc = const {},
    int? any,
    Map<int, double> pixelCounts = const {},
  }) {}

  @override
  Uint8List encryptVideoForGroup({
    required int ssrc,
    required Uint8List frame,
  }) {
    groupEncryptions.add(ssrc);
    return frame;
  }

  @override
  void sendPictureLoss({required int mediaSsrc}) {}

  @override
  Uint8List decryptVideoGroupFrame({
    required String userId,
    required Uint8List picture,
  }) => picture;

  @override
  void sendOpusFrame(Uint8List opusFrame) => opus.add(opusFrame);

  @override
  Future<void> finishSpeaking() async {}

  @override
  Future<void> connect() async => connects++;

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }
}
