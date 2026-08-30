import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/watched_stream_audio.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/voice_audio.dart';

import 'support/fake_voice_audio.dart';

const _key = GoLiveStreamKey.call(channelId: 'dm-1', userId: 'them');

const _otherKey = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'somebody-else',
);

/// An arriving Opus frame, as a stream connection delivers one.
VoiceRemoteOpusFrame _frame(String userId, List<int> opus) =>
    VoiceRemoteOpusFrame(userId: userId, opus: Uint8List.fromList(opus));

/// A connection's audio, as one the watcher is holding. Broadcast, because
/// the connection can outlive its watched session.
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
    opus.add(_frame('them', [7]));
    await _flush();

    expect(codecs.created, 1);
    expect(heard.single.userId, 'them');
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
    first.add(_frame('them', [1]));
    second.add(_frame('somebody-else', [2]));
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
    final subscription = audio.pcm.listen(heard.add);
    addTearDown(subscription.cancel);

    await audio.attach(_key, opus.stream);
    opus.add(_frame('them', [7]));
    await _flush();
    expect(heard, hasLength(1));

    await audio.detach(_key);
    expect(codecs.disposed, 1);

    // The connection Discord has not closed yet goes on delivering; nothing
    // is listening to it, and nothing comes out the other side.
    opus.add(_frame('them', [8]));
    await _flush();
    expect(heard, hasLength(1));
  });

  test('a stream nobody opened stays silent', () async {
    final codecs = FakeVoiceOpusDecoderFactory();
    final audio = WatchedStreamAudio(decoderFactory: codecs);
    addTearDown(audio.dispose);
    final opus = _connection();
    final heard = <VoiceRemotePcmFrame>[];
    final subscription = audio.pcm.listen(heard.add);
    addTearDown(subscription.cancel);

    opus.add(_frame('them', [7]));
    await _flush();

    expect(heard, isEmpty);
    expect(codecs.created, 0);
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
    first.add(_frame('them', [1]));
    await _flush();

    // A reconnect: the same stream, a new connection, and the decoder for the
    // old one is not the decoder for the new.
    await audio.attach(_key, reopened.stream);
    expect(codecs.disposed, 1);

    first.add(_frame('them', [2]));
    reopened.add(_frame('them', [3]));
    await _flush();

    expect(heard.map((frame) => frame.samples.single), [1, 3]);
    expect(codecs.created, 2);
  });
}
