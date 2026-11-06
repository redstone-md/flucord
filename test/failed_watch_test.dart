import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/data/discord/discord_stream_rtc_service.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/voice_connection.dart';

import 'support/stream_room_harness.dart';

const _key = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'friend-1',
);

/// One whole picture in one packet: a single keyframe unit, with the marker
/// that closes it.
final _picture = DiscordRtpFrame(
  header: DiscordRtpHeader(
    payloadType: DiscordRtpHeader.discordVideoPayloadType,
    sequence: 1,
    timestamp: 1,
    ssrc: 99,
    marker: true,
  ),
  payload: Uint8List.fromList([0x65, 0xaa, 0xaa]),
);

final _watchButton = find.byKey(const ValueKey('voice-watch-friend-1'));
final _failedMark = find.byKey(const ValueKey('voice-stream-error-friend-1'));

/// Presses Watch, and has Discord answer with an endpoint for it.
Future<void> _askAndAnswer(
  WidgetTester tester,
  StreamRoomHarness harness,
) async {
  await tester.tap(_watchButton);
  await tester.pump();
  harness.answerWatch(_key);
  await tester.pump();
}

/// A session Discord asked for and whose connection then fails.
Future<StreamRoomHarness> _failedWatch(WidgetTester tester) async {
  final harness = await pumpStreamRoom(tester, streamRoomVoiceChannel);
  await _askAndAnswer(tester, harness);
  harness.streamClients.single.emit(
    VoiceSignalingStatusEvent(
      VoiceConnectionStatus.failure,
      error: StateError('watch denied'),
    ),
  );
  await settleStreamRoom(tester);
  return harness;
}

void main() {
  testWidgets('a failed watch shows an error, and the tile offers Watch', (
    tester,
  ) async {
    await _failedWatch(tester);

    expect(_failedMark, findsOneWidget);
    expect(find.text('Stream unavailable'), findsOneWidget);
    expect(find.text('Stop watching'), findsNothing);
    expect(find.text('Watch stream'), findsOneWidget);
  });

  testWidgets('watching again withdraws first, and pictures flow', (
    tester,
  ) async {
    final harness = await _failedWatch(tester);

    await _askAndAnswer(tester, harness);

    expect(harness.repository.watchFrames, [
      'STREAM_WATCH ${_key.value}',
      'STREAM_DELETE ${_key.value}',
      'STREAM_WATCH ${_key.value}',
    ]);

    final fresh = harness.streamClients.last;
    fresh.emit(const VoiceTransportReadyEvent(streamRoomTransport));
    await settleStreamRoom(tester);
    fresh.emitVideo(_key.userId, _picture);
    await settleStreamRoom(tester);

    expect(harness.viewer.decodedUnitsFor(_key), 1);
    expect(_failedMark, findsNothing);
    expect(find.text('Stop watching'), findsOneWidget);

    await tester.runAsync(harness.viewer.stop);
  });

  testWidgets('a failed watch lets go of its connection', (tester) async {
    final harness = await _failedWatch(tester);

    expect(harness.streamClients.single.closed, isTrue);
    expect(harness.streamRtc.sessionFor(_key), isNull);
  });

  testWidgets('leaving the room after a failure leaves nothing behind', (
    tester,
  ) async {
    final harness = await _failedWatch(tester);
    final framesAtFailure = [...harness.repository.watchFrames];

    await harness.voice.disconnect();
    await settleStreamRoom(tester);
    await harness.joinRoom();
    await settleStreamRoom(tester);

    // Withdrawn once, at the failure: the room has nothing more to take back.
    expect(harness.repository.watchFrames, framesAtFailure);
    expect(harness.streamClients.single.closed, isTrue);
    expect(harness.viewer.isOpen(_key), isFalse);
    // The next time here is a new start, not last time's failure.
    expect(_failedMark, findsNothing);
    expect(find.text('Watch stream'), findsOneWidget);
  });

  testWidgets('a recovery that gives up before ready is a failed watch', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(tester, streamRoomVoiceChannel);
    await _askAndAnswer(tester, harness);

    await _exhaustRecovery(tester, harness);

    _expectGaveUp(harness);
  });

  testWidgets('a recovery that gives up after ready is a failed watch', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(tester, streamRoomVoiceChannel);
    await _askAndAnswer(tester, harness);
    harness.streamClients.single.emit(
      const VoiceTransportReadyEvent(streamRoomTransport),
    );
    await settleStreamRoom(tester);

    await _exhaustRecovery(tester, harness);

    _expectGaveUp(harness);
  });
}

/// Every endpoint Discord hands out dies before it is ready, until the service
/// stops asking for more.
Future<void> _exhaustRecovery(
  WidgetTester tester,
  StreamRoomHarness harness,
) async {
  for (var round = 0; round < DiscordStreamRtcService.maxRecoveries; round++) {
    harness.streamClients.last.emit(const VoiceCredentialsNeededEvent());
    await settleStreamRoom(tester);
    harness.answerWatch(_key);
    await settleStreamRoom(tester);
  }
  harness.streamClients.last.emit(const VoiceCredentialsNeededEvent());
  await settleStreamRoom(tester);
}

void _expectGaveUp(StreamRoomHarness harness) {
  expect(_failedMark, findsOneWidget);
  expect(find.text('Stop watching'), findsNothing);
  expect(find.text('Watch stream'), findsOneWidget);
  expect(harness.streamClients.every((client) => client.closed), isTrue);
  expect(harness.repository.watchFrames.last, 'STREAM_DELETE ${_key.value}');
}
