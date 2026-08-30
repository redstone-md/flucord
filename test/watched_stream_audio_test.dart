import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/watched_stream_audio.dart';
import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_voice_media_transport.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/voice_audio.dart';

import 'support/fake_voice_audio.dart';

const _key = GoLiveStreamKey.call(channelId: 'dm-1', userId: 'them');

const _otherKey = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'somebody-else',
);

/// Creates an Opus frame.
VoiceRemoteOpusFrame _opusFrame(String userId, List<int> opus) =>
    VoiceRemoteOpusFrame(userId: userId, opus: Uint8List.fromList(opus));

/// Creates an audio stream that can outlive a watched session.
StreamController<VoiceRemoteOpusFrame> _connection() {
  final controller = StreamController<VoiceRemoteOpusFrame>.broadcast();
  addTearDown(controller.close);
  return controller;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('a watched stream is decoded and tagged with its sender', () async {
    final codecs = FakeVoiceOpusDecoderFactory();
    final audio = WatchedStreamAudio(decoderFactory: codecs);
    addTearDown(audio.dispose);
    final opus = _connection();
    final heard = <VoiceRemotePcmFrame>[];
    final subscription = audio.pcm.listen(heard.add);
    addTearDown(subscription.cancel);

    await audio.attach(_key, opus.stream);
    opus.add(_opusFrame('them', [7]));
    await _flush();

    expect(codecs.created, 1);
    expect(heard.single.userId, 'them');
    expect(heard.single.sourceId, 'stream:call:dm-1:them:1');
    expect(heard.single.samples, [7]);
  });

  test('uses the stream media receive path before decoding', () async {
    final incoming = StreamController<DiscordRtpFrame>.broadcast();
    addTearDown(incoming.close);
    final transport = DiscordVoiceMediaTransport(
      incomingFrames: incoming.stream,
      encryptDave: (frame) => frame,
      decryptDave: (_, frame) => Uint8List.fromList(frame.sublist(1)),
      sendFrame: (_) => 1,
      sendSpeaking: (_) {},
      userForSsrc: (ssrc) => ssrc == 7 ? 'them' : null,
    )..configure(ssrc: 42, daveEnabled: true);
    final codecs = FakeVoiceOpusDecoderFactory();
    final audio = WatchedStreamAudio(decoderFactory: codecs);
    addTearDown(audio.dispose);
    final heard = <VoiceRemotePcmFrame>[];
    final subscription = audio.pcm.listen(heard.add);
    addTearDown(subscription.cancel);

    await audio.attach(_key, transport.remoteAudio);
    incoming.add(
      DiscordRtpFrame(
        header: DiscordRtpHeader(sequence: 1, timestamp: 1, ssrc: 7),
        payload: const [0xd0, 7],
      ),
    );
    await _flush();

    expect(heard.single.userId, 'them');
    expect(heard.single.sourceId, 'stream:call:dm-1:them:1');
    expect(heard.single.samples, [7]);
  });

  test('two watched streams keep a decoder each', () async {
    final codecs = FakeVoiceOpusDecoderFactory();
    final audio = WatchedStreamAudio(decoderFactory: codecs);
    addTearDown(audio.dispose);
    final first = _connection();
    final second = _connection();
    final heard = <VoiceRemotePcmFrame>[];
    final subscription = audio.pcm.listen(heard.add);
    addTearDown(subscription.cancel);

    await audio.attach(_key, first.stream);
    await audio.attach(_otherKey, second.stream);
    first.add(_opusFrame('them', [1]));
    second.add(_opusFrame('somebody-else', [2]));
    await _flush();

    expect(codecs.created, 2);
    expect(heard.map((frame) => frame.userId), ['them', 'somebody-else']);
    expect(heard.map((frame) => frame.samples.single), [1, 2]);
  });

  test('stopping a watch ends its sound and hands the decoder back', () async {
    final codecs = FakeVoiceOpusDecoderFactory();
    final audio = WatchedStreamAudio(decoderFactory: codecs);
    addTearDown(audio.dispose);
    final opus = _connection();
    final heard = <VoiceRemotePcmFrame>[];
    final ended = <String>[];
    final subscription = audio.pcm.listen(heard.add);
    final endedSubscription = audio.ended.listen(ended.add);
    addTearDown(subscription.cancel);
    addTearDown(endedSubscription.cancel);

    await audio.attach(_key, opus.stream);
    opus.add(_opusFrame('them', [7]));
    await _flush();
    expect(heard, hasLength(1));

    await audio.detach(_key);
    await _flush();
    expect(codecs.disposed, 1);
    expect(ended, ['stream:call:dm-1:them:1']);

    // Later packets are ignored after detach.
    opus.add(_opusFrame('them', [8]));
    await _flush();
    expect(heard, hasLength(1));
  });

  test('a reopened connection replaces the decoder behind it', () async {
    final codecs = FakeVoiceOpusDecoderFactory();
    final audio = WatchedStreamAudio(decoderFactory: codecs);
    addTearDown(audio.dispose);
    final first = _connection();
    final reopened = _connection();
    final heard = <VoiceRemotePcmFrame>[];
    final subscription = audio.pcm.listen(heard.add);
    addTearDown(subscription.cancel);

    await audio.attach(_key, first.stream);
    first.add(_opusFrame('them', [1]));
    await _flush();

    // A reconnect gets a new decoder.
    await audio.attach(_key, reopened.stream);
    expect(codecs.disposed, 1);

    first.add(_opusFrame('them', [2]));
    reopened.add(_opusFrame('them', [3]));
    await _flush();

    expect(heard.map((frame) => frame.samples.single), [1, 3]);
    expect(codecs.created, 2);
  });
}
