import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/data/discord/discord_rtp_packet.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/go_live_viewer.dart';

import 'support/fake_stream_client.dart';
import 'support/stream_room_harness.dart';

const _key = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: 'friend-1',
);

/// A tenth of a second of RTP ticks: far enough apart that a picture waits for
/// its slot, close enough that the slot still counts as a schedule.
const _gap = 9000;

/// Where a stream's clock starts: real streams start theirs at a random value.
const _start = 90000;

/// When a decoder is told the picture stamped [rtp] is due.
Duration _due(int rtp) => Duration(microseconds: rtp * 1000000 ~/ 90000);

/// One whole picture in one packet. Only a keyframe restarts a decoder.
DiscordRtpFrame _picture(int rtp, {bool keyframe = false}) => DiscordRtpFrame(
  header: DiscordRtpHeader(
    payloadType: DiscordRtpHeader.discordVideoPayloadType,
    sequence: rtp & 0xFFFF,
    timestamp: rtp,
    ssrc: 99,
    marker: true,
  ),
  payload: Uint8List.fromList([keyframe ? 0x65 : 0x41, 0xaa, 0xaa]),
);

/// A room with [_key]'s stream arriving, on the stage where the person put it
/// by pressing Watch.
Future<StreamRoomHarness> _watching(WidgetTester tester) async {
  final harness = await pumpStreamRoom(tester, streamRoomVoiceChannel);
  await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
  await tester.pump();
  harness.answerWatch(_key);
  await tester.pump();
  _connection(
    harness,
  ).emit(const VoiceTransportReadyEvent(streamRoomTransport));
  await settleStreamRoom(tester);
  expect(find.byType(GoLiveViewer), findsOneWidget);
  return harness;
}

FakeStreamClient _connection(StreamRoomHarness harness) =>
    harness.streamClients.single;

/// Ends the watch, which is real async work a fake-async body cannot wait out.
Future<void> _stop(WidgetTester tester, StreamRoomHarness harness) async {
  await tester.runAsync(harness.viewer.stop);
  await tester.pump();
}

void main() {
  testWidgets('pictures queued before a stall reach the decoder in order', (
    tester,
  ) async {
    final harness = await _watching(tester);
    final client = _connection(harness);

    client
      ..emitVideo(_key.userId, _picture(_start, keyframe: true))
      ..emitVideo(_key.userId, _picture(_start + _gap))
      ..emitVideo(_key.userId, _picture(_start + 2 * _gap));
    await tester.pump();

    // The UI thread is busy: no timer runs, and every slot goes by.
    sleep(const Duration(milliseconds: 400));
    client.emitVideo(_key.userId, _picture(_start + 3 * _gap));
    await tester.pump(const Duration(seconds: 1));

    expect(harness.openedViewerDecoders.single.submitted, [
      _due(_start),
      _due(_start + _gap),
      _due(_start + 2 * _gap),
      _due(_start + 3 * _gap),
    ]);

    await _stop(tester, harness);
  });
}
