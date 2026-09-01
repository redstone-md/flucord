import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_voice_socket_factory.dart';
import 'package:flucord/src/data/discord/go_live_media_worker.dart';
import 'package:flucord/src/data/discord/go_live_sender.dart';
import 'package:flucord/src/domain/go_live_media.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
);

const _credentials = VoiceServerCredentials(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
  sessionId: 'session-1',
  token: 'stream-token',
  endpoint: 'stream.discord.gg',
);

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

/// A worker in this isolate, with the main isolate's end faked by a port.
final class _Bench {
  _Bench() {
    toMain.listen(received.add);
    worker = GoLiveMediaWorker(
      toMain: toMain.sendPort,
      frames: const Stream<EncodedVideoFrame>.empty(),
      socketFactory: (maxDaveProtocolVersion) {
        daveVersions.add(maxDaveProtocolVersion);
        return _FakeSocketFactory(clients);
      },
    );
    addTearDown(() async {
      await inbox.close();
      toMain.close();
    });
  }

  final toMain = ReceivePort();
  final inbox = StreamController<Object?>();
  final received = <Object?>[];
  final clients = <_FakeClient>[];
  final daveVersions = <int>[];
  late final GoLiveMediaWorker worker;

  static const open = MediaOpen(
    id: 7,
    credentials: _credentials,
    streamKey: _key,
    settings: _settings,
    maxDaveProtocolVersion: 1,
  );

  /// Port messages cross on the event loop, behind a timer's turn.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  test('an open message opens a Sender through the injected factory', () async {
    final bench = _Bench();
    unawaited(bench.worker.run(bench.inbox.stream));

    bench.inbox.add(_Bench.open);
    await bench.settle();

    expect(bench.daveVersions, [1]);
    expect(bench.clients.single.connects, 1);
  });

  test('status and commands cross back under the Sender\'s id', () async {
    final bench = _Bench();
    unawaited(bench.worker.run(bench.inbox.stream));
    bench.inbox.add(_Bench.open);
    await bench.settle();
    final client = bench.clients.single;

    client.emit(const VoiceTransportReadyEvent(_session));
    client.emit(const VoiceKeyframeRequestedEvent());
    await bench.settle();

    // Announced on the worker with the settings it was opened with.
    expect(client.announcements.single.settings, _settings);
    expect(
      bench.received.whereType<MediaStatus>().map((m) => (m.id, m.status)),
      [(7, GoLiveSenderStatus.ready)],
    );
    // The keyframe on announce, then the one the watcher asked for.
    expect(
      bench.received.whereType<MediaCommand>().map((m) => m.command),
      everyElement(isA<GoLiveKeyframeCommand>()),
    );
    expect(bench.received.whereType<MediaCommand>(), hasLength(2));
  });

  test('a reshape and sound reach the Sender, a close closes it', () async {
    final bench = _Bench();
    unawaited(bench.worker.run(bench.inbox.stream));
    bench.inbox.add(_Bench.open);
    await bench.settle();
    final client = bench.clients.single;
    client.emit(const VoiceTransportReadyEvent(_session));

    const taller = VideoEncoderSettings(
      bitrate: 4000000,
      width: 1920,
      height: 1080,
      framesPerSecond: 60,
    );
    bench.inbox.add(const MediaReshape(id: 7, settings: taller));
    bench.inbox.add(MediaAudio(id: 7, opus: Uint8List.fromList([1, 2])));
    await bench.settle();
    expect(client.announcements.last.settings, taller);
    expect(client.opus, hasLength(1));

    bench.inbox.add(const MediaClose(7));
    await bench.settle();
    await bench.settle();
    expect(client.closed, isTrue);
    expect(bench.received.whereType<MediaClosed>().single.id, 7);
  });

  test('a message that throws is logged and the loop goes on', () async {
    final bench = _Bench();
    unawaited(bench.worker.run(bench.inbox.stream));
    bench.inbox.add(_Bench.open);
    await bench.settle();
    final client = bench.clients.single..throwOnOpus = true;
    client.emit(const VoiceTransportReadyEvent(_session));

    bench.inbox.add(MediaAudio(id: 7, opus: Uint8List.fromList([1])));
    bench.inbox.add(const MediaClose(7));
    await bench.settle();
    await bench.settle();

    expect(
      bench.received.whereType<MediaLog>().single.message,
      'message failed',
    );
    // The close after the bad message was still handled.
    expect(client.closed, isTrue);
  });

  test('a shutdown closes every Sender and ends the loop', () async {
    final bench = _Bench();
    final done = bench.worker.run(bench.inbox.stream);
    bench.inbox.add(_Bench.open);
    await bench.settle();

    bench.inbox.add(const MediaShutdown());
    await done;

    expect(bench.clients.single.closed, isTrue);
  });
}

final class _FakeSocketFactory implements DiscordVoiceSocketFactory {
  _FakeSocketFactory(this._clients);

  final List<_FakeClient> _clients;

  @override
  int get maxDaveProtocolVersion => 0;

  @override
  DiscordVoiceClient callSocket(VoiceServerCredentials credentials) =>
      throw UnsupportedError('the media worker dials no call sockets');

  @override
  DiscordVoiceClient streamSocket({
    required VoiceServerCredentials credentials,
    required GoLiveStreamKey streamKey,
  }) {
    final client = _FakeClient();
    _clients.add(client);
    return client;
  }
}

final class _FakeClient implements DiscordVoiceClient, VoiceAudioTransport {
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast(sync: true);
  final List<({bool enabled, VideoEncoderSettings settings})> announcements =
      [];
  final List<Uint8List> opus = [];
  int connects = 0;
  bool closed = false;
  bool throwOnOpus = false;

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
  int sendVideoFrame(DiscordRtpFrame frame) => frame.payload.length;

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
  }) => frame;

  @override
  void sendPictureLoss({required int mediaSsrc}) {}

  @override
  Uint8List decryptVideoGroupFrame({
    required String userId,
    required Uint8List picture,
  }) => picture;

  @override
  void sendOpusFrame(Uint8List opusFrame) {
    if (throwOnOpus) throw StateError('no audio path');
    opus.add(opusFrame);
  }

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
