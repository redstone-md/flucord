import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/stream_suspension.dart';
import 'package:flucord/src/application/window_visible.dart';
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

/// The window this room is drawn in, wired the way the app wires it.
WindowVisible _window(StreamRoomHarness harness) {
  final window = WindowVisible();
  final suspension = StreamSuspension(
    visible: window,
    viewer: harness.viewer,
    remoteCameras: harness.composition.remoteCameras,
  );
  addTearDown(window.dispose);
  addTearDown(suspension.dispose);
  return window;
}

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

  testWidgets('a session waits for a tile before it opens a decoder', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(tester, streamRoomVoiceChannel);

    // Held, and arriving, with the stage on nobody.
    await tester.runAsync(() => harness.viewer.requestWatch(_key));
    harness.answerWatch(_key);
    await tester.pump();
    _connection(
      harness,
    ).emit(const VoiceTransportReadyEvent(streamRoomTransport));
    await settleStreamRoom(tester);
    _connection(
      harness,
    ).emitVideo(_key.userId, _picture(_start, keyframe: true));
    await settleStreamRoom(tester);

    expect(harness.viewer.receivedPacketsFor(_key), 1);
    expect(harness.openedViewerDecoders, isEmpty);

    harness.focus.focus(_key.userId);
    await settleStreamRoom(tester);
    _connection(
      harness,
    ).emitVideo(_key.userId, _picture(_start + _gap, keyframe: true));
    await settleStreamRoom(tester);

    expect(harness.openedViewerDecoders.single.submitted, [
      _due(_start + _gap),
    ]);

    await _stop(tester, harness);
  });

  testWidgets('reading a text channel lets go of the decoder and keeps the '
      'connection', (tester) async {
    final harness = await _watching(tester);
    final decoder = harness.openedViewerDecoders.single;
    _connection(
      harness,
    ).emitVideo(_key.userId, _picture(_start, keyframe: true));
    await settleStreamRoom(tester);
    expect(decoder.submitted, hasLength(1));

    await tester.pumpWidget(harness.pane(showing: streamRoomCall));
    await settleStreamRoom(tester);

    expect(find.byType(GoLiveViewer), findsNothing);
    expect(decoder.stopped, 1);

    _connection(
      harness,
    ).emitVideo(_key.userId, _picture(_start + _gap, keyframe: true));
    await settleStreamRoom(tester);

    expect(harness.openedViewerDecoders, [decoder]);
    expect(decoder.submitted, hasLength(1));
    expect(harness.viewer.receivedPacketsFor(_key), 2);
    expect(_connection(harness).closed, isFalse);
    expect(harness.viewer.isWatching(_key), isTrue);
    expect(harness.repository.watchFrames, ['STREAM_WATCH ${_key.value}']);

    await _stop(tester, harness);
  });

  testWidgets('coming back to the tile asks for a keyframe and resumes', (
    tester,
  ) async {
    final harness = await _watching(tester);
    final client = _connection(harness);
    client.emitVideo(_key.userId, _picture(_start, keyframe: true));
    await settleStreamRoom(tester);
    await tester.pumpWidget(harness.pane(showing: streamRoomCall));
    await settleStreamRoom(tester);

    await tester.pumpWidget(harness.pane());
    await settleStreamRoom(tester);

    final decoder = harness.openedViewerDecoders.last;
    expect(harness.openedViewerDecoders, hasLength(2));

    // The new decoder has nothing to build on, so this picture is held back
    // and the sender is asked for one that restarts it.
    client.emitVideo(_key.userId, _picture(_start + _gap));
    await settleStreamRoom(tester);
    expect(decoder.submitted, isEmpty);
    expect(client.keyframeAsks, 1);

    client.emitVideo(_key.userId, _picture(_start + 2 * _gap, keyframe: true));
    await settleStreamRoom(tester);
    expect(decoder.submitted, [_due(_start + 2 * _gap)]);

    await _stop(tester, harness);
  });

  testWidgets('a room redrawn around its tile keeps the decoder', (
    tester,
  ) async {
    final harness = await _watching(tester);

    // Anything the viewer announces redraws the room, tile included.
    await tester.runAsync(
      () => harness.viewer.requestWatch(
        const GoLiveStreamKey.guild(
          guildId: 'guild-1',
          channelId: 'voice-1',
          userId: 'friend-2',
        ),
      ),
    );
    await settleStreamRoom(tester);

    expect(find.byType(GoLiveViewer), findsOneWidget);
    final decoder = harness.openedViewerDecoders.single;
    expect(decoder.stopped, 0);

    await _stop(tester, harness);
  });

  testWidgets('a connection reopened under the tile goes on drawing', (
    tester,
  ) async {
    final harness = await _watching(tester);

    harness.answerWatch(_key);
    await settleStreamRoom(tester);
    final reopened = harness.streamClients.last;
    reopened.emit(const VoiceTransportReadyEvent(streamRoomTransport));
    await settleStreamRoom(tester);
    await settleStreamRoom(tester);
    reopened.emitVideo(_key.userId, _picture(_start, keyframe: true));
    await settleStreamRoom(tester);

    expect(harness.openedViewerDecoders, hasLength(2));
    expect(harness.openedViewerDecoders.last.submitted, [_due(_start)]);

    await _stop(tester, harness);
  });

  testWidgets('a suspended client keeps receiving and draws nothing', (
    tester,
  ) async {
    final harness = await _watching(tester);
    final window = _window(harness);
    final decoder = harness.openedViewerDecoders.single;

    window.setInView(false);
    await settleStreamRoom(tester);

    // The tile is still there; the window is what nobody can see.
    expect(find.byType(GoLiveViewer), findsOneWidget);
    expect(decoder.stopped, 1);

    _connection(
      harness,
    ).emitVideo(_key.userId, _picture(_start, keyframe: true));
    await settleStreamRoom(tester);

    expect(harness.viewer.receivedPacketsFor(_key), 1);
    expect(harness.openedViewerDecoders, [decoder]);
    expect(_connection(harness).closed, isFalse);

    window.setInView(true);
    await settleStreamRoom(tester);
    expect(harness.openedViewerDecoders, hasLength(2));

    await _stop(tester, harness);
  });

  testWidgets('a window coming back opens nothing for a tile that went away', (
    tester,
  ) async {
    final harness = await _watching(tester);
    final window = _window(harness);

    window.setInView(false);
    await settleStreamRoom(tester);
    harness.focus.clear();
    await settleStreamRoom(tester);
    window.setInView(true);
    await settleStreamRoom(tester);

    expect(harness.openedViewerDecoders, hasLength(1));

    await _stop(tester, harness);
  });

  testWidgets('a window behind another still draws', (tester) async {
    final harness = await _watching(tester);
    final window = _window(harness);
    final decoder = harness.openedViewerDecoders.single;

    window.setFocused(false);
    await settleStreamRoom(tester);
    _connection(
      harness,
    ).emitVideo(_key.userId, _picture(_start, keyframe: true));
    await settleStreamRoom(tester);

    expect(decoder.stopped, 0);
    expect(decoder.submitted, [_due(_start)]);

    await _stop(tester, harness);
  });

  testWidgets('a decoder that will not open says so on the tile', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(tester, streamRoomVoiceChannel);
    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
    await tester.pump();
    harness.answerWatch(_key);
    await tester.pump();
    harness.viewerDecoderFails = true;
    _connection(
      harness,
    ).emit(const VoiceTransportReadyEvent(streamRoomTransport));
    await settleStreamRoom(tester);
    await settleStreamRoom(tester);

    expect(find.text('Stream unavailable'), findsOneWidget);
    expect(harness.viewer.isWatching(_key), isTrue);

    await _stop(tester, harness);
  });
}
