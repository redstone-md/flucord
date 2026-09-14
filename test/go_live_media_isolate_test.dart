import 'package:flucord/src/data/discord/go_live_media_isolate.dart';
import 'package:flucord/src/data/discord/go_live_sender.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/video_encoder.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the media isolate answers where frames go, and shuts down', () async {
    final plane = GoLiveMediaIsolate();

    // An address on a machine with the native module, nothing on a host
    // without one; either way the worker came up and answered.
    final sink = await plane.nativeFrameSink;
    expect(sink, anyOf(isNull, isPositive));

    await plane.dispose();
  });

  test('a disposed plane hands out no sink, and opens no sender', () async {
    final plane = GoLiveMediaIsolate();
    await plane.nativeFrameSink;

    await plane.dispose();

    // The worker closed its native frame callback during the shutdown: a
    // stale address would hand a newly opened encoder a callback that no
    // longer exists.
    expect(await plane.nativeFrameSink, isNull);

    final statuses = <GoLiveSenderStatus>[];
    final sender = plane.openSender(
      credentials: const VoiceServerCredentials(
        guildId: 'g',
        channelId: 'c',
        userId: 'me',
        sessionId: 's',
        token: 't',
        endpoint: 'e',
      ),
      streamKey: const GoLiveStreamKey.call(channelId: 'c', userId: 'me'),
      settings: const VideoEncoderSettings(bitrate: 1000000),
    );
    sender.statuses.listen(statuses.add);
    await pumpEventQueue();

    expect(statuses, [GoLiveSenderStatus.failed]);
    await sender.close();
  });
}
