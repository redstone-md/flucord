import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/data/discord/discord_voice_media_transport.dart';

void main() {
  test(
    'sends DAVE RTP, speaking flags, and five trailing silence frames',
    () async {
      final incoming = StreamController<DiscordRtpFrame>.broadcast();
      addTearDown(incoming.close);
      final sent = <DiscordRtpFrame>[];
      final speaking = <bool>[];
      final transport = DiscordVoiceMediaTransport(
        incomingFrames: incoming.stream,
        encryptDave: (opus) => Uint8List.fromList([0xd0, ...opus]),
        decryptDave: (_, frame) => frame,
        sendFrame: (frame) {
          sent.add(frame);
          return frame.payload.length + 12;
        },
        sendSpeaking: speaking.add,
        userForSsrc: (_) => null,
      )..configure(ssrc: 42, daveEnabled: true);

      transport.sendOpusFrame(Uint8List.fromList([1, 2]));
      transport.sendOpusFrame(Uint8List.fromList([3]));
      await transport.finishSpeaking();

      expect(speaking, [true, false]);
      expect(sent, hasLength(7));
      expect(sent.first.header.marker, isTrue);
      expect(sent[1].header.marker, isFalse);
      expect(sent.first.payload, [0xd0, 1, 2]);
      expect(sent.last.payload, [0xd0, 0xf8, 0xff, 0xfe]);
      expect(
        sent.last.header.sequence,
        (sent.first.header.sequence + 6) & 0xffff,
      );
    },
  );

  test('a frame the socket refuses is dropped until they all are', () {
    var accept = false;
    var refused = 0;
    final incoming = StreamController<DiscordRtpFrame>.broadcast();
    addTearDown(incoming.close);
    final transport = DiscordVoiceMediaTransport(
      incomingFrames: incoming.stream,
      encryptDave: (opus) => opus,
      decryptDave: (_, frame) => frame,
      sendFrame: (frame) {
        if (accept) return frame.payload.length + 12;
        refused++;
        return 0;
      },
      sendSpeaking: (_) {},
      userForSsrc: (_) => null,
    )..configure(ssrc: 42, daveEnabled: false);

    // Twenty milliseconds of audio lost to a socket being replaced is every
    // reconnect. Reporting each one put "voice ran into a problem" over a call
    // that was recovering perfectly well.
    for (var index = 0; index < 49; index++) {
      transport.sendOpusFrame(Uint8List.fromList([1]));
    }
    expect(refused, 49);

    // A path that is genuinely gone still says so.
    expect(
      () => transport.sendOpusFrame(Uint8List.fromList([1])),
      throwsStateError,
    );

    accept = true;
    transport.sendOpusFrame(Uint8List.fromList([1]));
    accept = false;
    for (var index = 0; index < 49; index++) {
      transport.sendOpusFrame(Uint8List.fromList([1]));
    }

    // The count starts again after a frame that landed.
    expect(
      () => transport.sendOpusFrame(Uint8List.fromList([1])),
      throwsStateError,
    );
  });

  test('a packet the group key cannot open is dropped, not decoded', () async {
    final incoming = StreamController<DiscordRtpFrame>.broadcast();
    addTearDown(incoming.close);
    final transport = DiscordVoiceMediaTransport(
      incomingFrames: incoming.stream,
      encryptDave: (opus) => opus,
      decryptDave: (_, _) => throw StateError('no key for that sender yet'),
      sendFrame: (frame) => frame.payload.length,
      sendSpeaking: (_) {},
      userForSsrc: (_) => 'them',
    )..configure(ssrc: 42, daveEnabled: true);
    final received = <VoiceRemoteOpusFrame>[];
    final subscription = transport.remoteAudio.listen(received.add);
    addTearDown(subscription.cancel);

    incoming.add(
      DiscordRtpFrame(
        header: DiscordRtpHeader(sequence: 1, timestamp: 1, ssrc: 7),
        payload: const [1, 2, 3],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Carried on, the Opus decoder answers an empty buffer with "invalid
    // argument" and the room reports a broken call. A sender's key arrives
    // after their first packets do, so this is ordinary.
    expect(received, isEmpty);
  });

  test('maps SSRC, decrypts DAVE, and drops unknown senders', () async {
    final incoming = StreamController<DiscordRtpFrame>.broadcast();
    addTearDown(incoming.close);
    final transport = DiscordVoiceMediaTransport(
      incomingFrames: incoming.stream,
      encryptDave: (frame) => frame,
      decryptDave: (_, frame) => Uint8List.fromList(frame.sublist(1)),
      sendFrame: (_) => 1,
      sendSpeaking: (_) {},
      userForSsrc: (ssrc) => ssrc == 77 ? 'user-1' : null,
    )..configure(ssrc: 42, daveEnabled: true);
    final received = transport.remoteAudio.first;

    incoming.add(_frame(ssrc: 99, payload: [0xd0, 1]));
    incoming.add(_frame(ssrc: 77, payload: [0xd0, 2, 3]));

    final result = await received;
    expect(result.userId, 'user-1');
    expect(result.opus, [2, 3]);
  });

  test('reorders remote RTP before DAVE decryption and drops replay', () async {
    final incoming = StreamController<DiscordRtpFrame>.broadcast();
    addTearDown(incoming.close);
    final decryptedSequences = <int>[];
    final transport = DiscordVoiceMediaTransport(
      incomingFrames: incoming.stream,
      encryptDave: (frame) => frame,
      decryptDave: (_, frame) {
        decryptedSequences.add(frame.first);
        return frame;
      },
      sendFrame: (_) => 1,
      sendSpeaking: (_) {},
      userForSsrc: (_) => 'user-1',
    )..configure(ssrc: 42, daveEnabled: true);
    final received = transport.remoteAudio.take(3).toList();

    incoming.add(_frame(ssrc: 77, sequence: 10, payload: [10]));
    incoming.add(_frame(ssrc: 77, sequence: 12, payload: [12]));
    incoming.add(_frame(ssrc: 77, sequence: 12, payload: [12]));
    incoming.add(_frame(ssrc: 77, sequence: 11, payload: [11]));

    expect((await received).map((frame) => frame.opus.single), [10, 11, 12]);
    expect(decryptedSequences, [10, 11, 12]);
  });

  test('reports an RTP gap on the first frame after skipped loss', () async {
    final incoming = StreamController<DiscordRtpFrame>.broadcast();
    addTearDown(incoming.close);
    final transport = DiscordVoiceMediaTransport(
      incomingFrames: incoming.stream,
      encryptDave: (frame) => frame,
      decryptDave: (_, frame) => frame,
      sendFrame: (_) => 1,
      sendSpeaking: (_) {},
      userForSsrc: (_) => 'user-1',
    )..configure(ssrc: 42, daveEnabled: false);
    final received = transport.remoteAudio.take(4).toList();

    incoming.add(_frame(ssrc: 77, sequence: 10, payload: [10]));
    incoming.add(_frame(ssrc: 77, sequence: 12, payload: [12]));
    incoming.add(_frame(ssrc: 77, sequence: 13, payload: [13]));
    incoming.add(_frame(ssrc: 77, sequence: 14, payload: [14]));

    final frames = await received;
    expect(frames.map((frame) => frame.missingFramesBefore), [0, 1, 0, 0]);
  });

  test('refuses media before configure and after reset', () {
    final transport = DiscordVoiceMediaTransport(
      incomingFrames: const Stream.empty(),
      encryptDave: (frame) => frame,
      decryptDave: (_, frame) => frame,
      sendFrame: (_) => 1,
      sendSpeaking: (_) {},
      userForSsrc: (_) => null,
    );
    final opus = Uint8List.fromList([1]);
    expect(() => transport.sendOpusFrame(opus), throwsStateError);
    transport.configure(ssrc: 1, daveEnabled: false);
    transport.reset();
    expect(() => transport.sendOpusFrame(opus), throwsStateError);
  });
}

DiscordRtpFrame _frame({
  required int ssrc,
  required List<int> payload,
  int sequence = 1,
}) => DiscordRtpFrame(
  header: DiscordRtpHeader(sequence: sequence, timestamp: 2, ssrc: ssrc),
  payload: payload,
);
