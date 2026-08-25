import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/data/discord/go_live_sending_client.dart';
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

/// A sending client over a fake connection, announced and ready to send.
({
  GoLiveSendingClient client,
  _FakeClient inner,
  List<GoLiveEncoderCommand> commands,
  StreamController<EncodedVideoFrame> frames,
})
_announced() {
  final inner = _FakeClient();
  final frames = StreamController<EncodedVideoFrame>.broadcast();
  final commands = <GoLiveEncoderCommand>[];
  final client = GoLiveSendingClient(
    inner: inner,
    frames: frames.stream,
    onEncoderCommand: commands.add,
  );
  addTearDown(client.close);
  inner.emit(const VoiceTransportReadyEvent(_session));
  client.announceVideo(enabled: true, settings: _settings);
  return (client: client, inner: inner, commands: commands, frames: frames);
}

void main() {
  test(
    'announces, then sends the pictures on the SSRC above the connection\'s',
    () async {
      final inner = _FakeClient();
      final frames = StreamController<EncodedVideoFrame>.broadcast();
      final commands = <GoLiveEncoderCommand>[];
      final client = GoLiveSendingClient(
        inner: inner,
        frames: frames.stream,
        onEncoderCommand: commands.add,
      );
      addTearDown(client.close);

      // Nothing to send on before the connection is ready and announced.
      expect(client.takePaceLine(), isNull);
      inner.emit(const VoiceTransportReadyEvent(_session));
      client.announceVideo(enabled: true, settings: _settings);
      expect(inner.announcements.single.settings, _settings);
      // The encoder's first keyframe is long gone: one is asked for at once.
      expect(commands, [isA<GoLiveKeyframeCommand>()]);

      frames.add(
        EncodedVideoFrame(
          bytes: _keyframe,
          timestamp: const Duration(milliseconds: 100),
          isKeyframe: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(inner.sentFrames, isNotEmpty);
      expect(
        inner.sentFrames.every((frame) => frame.header.ssrc == 4243),
        isTrue,
      );
      // Encrypted for the group once, as a whole picture, before packetising.
      expect(inner.groupEncryptions, [4243]);
      expect(client.takePaceLine(), contains('healthy'));
    },
  );

  test(
    'loss the server reports lowers the bitrate, a clean path restores it',
    () {
      final (:client, :inner, :commands, frames: _) = _announced();
      commands.clear();

      inner.emit(
        const VoiceReceiverReportEvent(
          ssrc: 4243,
          lossRatio: 0.2,
          cumulativeLost: 9,
        ),
      );
      // Backed off by half the loss.
      expect(commands, [isA<GoLiveBitrateCommand>()]);
      expect((commands.single as GoLiveBitrateCommand).bitsPerSecond, 2250000);

      inner.emit(
        const VoiceReceiverReportEvent(
          ssrc: 4243,
          lossRatio: 0,
          cumulativeLost: 9,
        ),
      );
      expect((commands.last as GoLiveBitrateCommand).bitsPerSecond, 2430000);
      expect(client.takePaceLine(), contains('bitrate 2430k'));
    },
  );

  test('a missed packet is resent, a lost picture asks the encoder', () async {
    final (:client, :inner, :commands, :frames) = _announced();
    frames.add(
      EncodedVideoFrame(
        bytes: _keyframe,
        timestamp: const Duration(milliseconds: 100),
        isKeyframe: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final sent = inner.sentFrames.length;

    // Answered from the sender's history, on the rtx SSRC (one above the
    // video's), not by the encoder being asked to redraw.
    inner.emit(const VoiceRetransmitRequestedEvent(ssrc: 4243, sequences: [0]));
    expect(inner.sentFrames.length, sent + 1);
    expect(inner.sentFrames.last.header.ssrc, 4244);

    commands.clear();
    inner.emit(const VoiceKeyframeRequestedEvent());
    expect(commands, [isA<GoLiveKeyframeCommand>()]);
    expect(client.takePaceLine(), contains('1/1 resent, 1 keyframe req'));
  });

  test('sound goes through the connection\'s own audio path once ready', () {
    final inner = _FakeClient();
    final client = GoLiveSendingClient(
      inner: inner,
      frames: const Stream<EncodedVideoFrame>.empty(),
      onEncoderCommand: (_) {},
    );
    addTearDown(client.close);

    // The capture produces sound before the endpoint answered; a frame sent
    // then is dropped rather than thrown at a transport that is not up.
    client.sendOpusFrame(Uint8List.fromList([1, 2, 3]));
    expect(inner.opus, isEmpty);

    inner.emit(const VoiceTransportReadyEvent(_session));
    client.sendOpusFrame(Uint8List.fromList([1, 2, 3]));
    expect(inner.opus, hasLength(1));
  });

  test('closing closes the connection and says so', () async {
    final inner = _FakeClient();
    var closed = 0;
    final client = GoLiveSendingClient(
      inner: inner,
      frames: const Stream<EncodedVideoFrame>.empty(),
      onEncoderCommand: (_) {},
      onClosed: () => closed++,
    );

    await client.close();

    expect(inner.closed, isTrue);
    expect(closed, 1);
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
  Uint8List encryptVideoForGroup({
    required int ssrc,
    required Uint8List frame,
  }) {
    groupEncryptions.add(ssrc);
    return frame;
  }

  @override
  void sendOpusFrame(Uint8List opusFrame) => opus.add(opusFrame);

  @override
  Future<void> finishSpeaking() async {}

  @override
  Future<void> connect() async {}

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }
}
