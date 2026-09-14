import 'dart:async';
import 'dart:typed_data';

import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_gateway_client.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';

/// The wire client under a Sender, faked: records what was announced and
/// sent, and lets the test speak for the far end through [emit].
final class FakeStreamClient
    implements DiscordVoiceClient, VoiceAudioTransport {
  final StreamController<VoiceSignalingEvent> _events =
      StreamController.broadcast(sync: true);
  final List<DiscordRtpFrame> sentFrames = [];
  final List<({bool enabled, VideoEncoderSettings settings})> announcements =
      [];

  /// The SSRC each whole picture was group-encrypted for.
  final List<int> groupEncryptions = [];
  final List<Uint8List> opus = [];
  int connects = 0;
  bool closed = false;

  /// A connection whose audio path refuses: what a fault on the worker
  /// looks like.
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
