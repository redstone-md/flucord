import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/voice_connection.dart';

import 'support/stream_room_harness.dart';

const _key = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'me',
);

final _toggle = find.byKey(const ValueKey('go-live-toggle'));

/// The server room with this account's stream up, as far as Discord answering
/// it with a stream and an endpoint.
Future<StreamRoomHarness> _liveRoom(WidgetTester tester) async {
  final harness = await pumpStreamRoom(tester, streamRoomVoiceChannel);
  await tester.tap(_toggle);
  await tester.pumpAndSettle();
  harness.repository
    ..dispatch('STREAM_CREATE', {'stream_key': _key.value})
    ..dispatch('STREAM_SERVER_UPDATE', {
      'stream_key': _key.value,
      'endpoint': 'stream.discord.gg',
      'token': 'stream-token',
    });
  await tester.pumpAndSettle();
  expect(harness.goLive.status, GoLiveStatus.live);
  return harness;
}

/// The share is over on this machine and nothing still holds the capture.
void _expectEnded(StreamRoomHarness harness) {
  expect(harness.goLive.status, GoLiveStatus.idle);
  expect(harness.encoder.stopped, 1);
  expect(find.byTooltip('Stop streaming'), findsNothing);
}

/// The stream is still up, and still capturing.
void _expectStillLive(StreamRoomHarness harness) {
  expect(harness.goLive.status, GoLiveStatus.live);
  expect(harness.encoder.stopped, 0);
  expect(harness.repository.ended, isEmpty);
}

void main() {
  testWidgets('leaving the room ends the stream and its capture', (
    tester,
  ) async {
    final harness = await _liveRoom(tester);

    await harness.voice.disconnect();
    await tester.pumpAndSettle();

    _expectEnded(harness);
    expect(harness.repository.ended, [_key]);
  });

  testWidgets('a room that fails ends the stream and its capture', (
    tester,
  ) async {
    final harness = await _liveRoom(tester);

    harness.signaling.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.failure),
    );
    await tester.pumpAndSettle();

    _expectEnded(harness);
    expect(harness.repository.ended, [_key]);
  });

  testWidgets('moving to a room in another guild ends the stream', (
    tester,
  ) async {
    final harness = await _liveRoom(tester);

    await harness.voice.connect(guildId: 'guild-2', channelId: 'voice-2');
    await tester.pumpAndSettle();

    _expectEnded(harness);
    expect(harness.repository.ended, [_key]);
  });

  testWidgets('a move by Discord to another channel ends the stream', (
    tester,
  ) async {
    final harness = await _liveRoom(tester);

    harness.signaling.emit(
      const VoiceMovedToChannelEvent(guildId: 'guild-1', channelId: 'voice-2'),
    );
    await tester.pumpAndSettle();

    // The stream's key names the old channel, and Discord ends it there.
    _expectEnded(harness);
    expect(harness.repository.ended, [_key]);
  });

  testWidgets('moving from a server room into a call ends the stream', (
    tester,
  ) async {
    final harness = await _liveRoom(tester);

    await harness.voice.connectToCall(channelId: 'dm-1');
    await tester.pumpAndSettle();

    _expectEnded(harness);
    expect(harness.repository.ended, [_key]);
  });

  testWidgets('moving from one call to another ends the stream', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(tester, streamRoomCall);
    await tester.tap(_toggle);
    await tester.pumpAndSettle();

    await harness.voice.connectToCall(channelId: 'dm-2');
    await tester.pumpAndSettle();

    _expectEnded(harness);
    expect(harness.repository.ended, [
      const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'me'),
    ]);
  });

  testWidgets('a stream Discord deleted ends here, with no delete sent back', (
    tester,
  ) async {
    final harness = await _liveRoom(tester);

    harness.repository.dispatch('STREAM_DELETE', {'stream_key': _key.value});
    await tester.pumpAndSettle();

    _expectEnded(harness);
    expect(harness.repository.ended, isEmpty);
  });

  testWidgets('a delete for somebody else in the room changes nothing', (
    tester,
  ) async {
    final harness = await _liveRoom(tester);
    const other = GoLiveStreamKey.guild(
      guildId: 'guild-1',
      channelId: 'voice-1',
      userId: 'friend-1',
    );

    harness.repository
      ..dispatch('STREAM_CREATE', {'stream_key': other.value})
      ..dispatch('STREAM_DELETE', {'stream_key': other.value});
    await tester.pumpAndSettle();

    _expectStillLive(harness);

    await tester.tap(_toggle);
    await tester.pumpAndSettle();
  });

  testWidgets('a reconnect waiting for a new session keeps the stream', (
    tester,
  ) async {
    final harness = await _liveRoom(tester);

    // A session-ended close on the voice socket: the room is shown as
    // reconnecting while the gateway hands out fresh credentials.
    harness.signaling
      ..emit(const VoiceCredentialsNeededEvent())
      ..emit(
        const VoiceSignalingStatusEvent(VoiceConnectionStatus.reconnecting),
      );
    await tester.pumpAndSettle();
    _expectStillLive(harness);

    harness.signaling.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.ready),
    );
    await tester.pumpAndSettle();
    _expectStillLive(harness);

    await tester.tap(_toggle);
    await tester.pumpAndSettle();
  });

  testWidgets('a change to a stream that still exists keeps it', (
    tester,
  ) async {
    final harness = await _liveRoom(tester);

    harness.repository.dispatch('STREAM_UPDATE', {
      'stream_key': _key.value,
      'viewer_ids': ['friend-1', 'friend-2'],
    });
    await tester.pumpAndSettle();

    _expectStillLive(harness);
    expect(harness.goLive.viewerIds, ['friend-1', 'friend-2']);

    await tester.tap(_toggle);
    await tester.pumpAndSettle();
  });

  group('after a stream ended', () {
    final endings = <String, Future<void> Function(StreamRoomHarness)>{
      // Walks back in, because a stream or a camera needs a room to go into.
      'with the room': (harness) async {
        await harness.voice.disconnect();
        await harness.joinRoom();
      },
      'by Discord': (harness) async => harness.repository.dispatch(
        'STREAM_DELETE',
        {'stream_key': _key.value},
      ),
    };

    endings.forEach((name, end) {
      testWidgets('$name, a new stream can start', (tester) async {
        final harness = await _liveRoom(tester);
        await end(harness);
        await tester.pumpAndSettle();

        await tester.tap(_toggle);
        await tester.pumpAndSettle();

        expect(harness.goLive.error, isNull);
        expect(harness.goLive.status, GoLiveStatus.creating);
        expect(harness.encoder.started, hasLength(2));
        expect(harness.repository.startedChannels, ['voice-1', 'voice-1']);

        await tester.tap(_toggle);
        await tester.pumpAndSettle();
      });

      testWidgets('$name, a camera can start', (tester) async {
        final harness = await _liveRoom(tester);
        await end(harness);
        await tester.pumpAndSettle();

        expect(await harness.camera.turnOn(), isTrue);
        await tester.pumpAndSettle();

        expect(harness.camera.isOn, isTrue);
        expect(harness.camera.error, isNull);
        expect(harness.encoder.started, hasLength(2));
        expect(harness.cameraTransport.announcements, [true]);
      });
    });
  });
}
