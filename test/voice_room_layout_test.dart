import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/chat_header.dart';
import 'package:flucord/src/presentation/widgets/soundboard_picker.dart';
import 'package:flucord/src/presentation/widgets/voice_room_controls.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/flucord_icon_finder.dart';
import 'support/stream_room_harness.dart';

final _surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;

const _session = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 1,
  address: '127.0.0.1',
  port: 1000,
  mode: 'aead_aes256_gcm_rtpsize',
  secretKey: [1],
  daveProtocolVersion: 0,
);

/// The voice connection comes up, and its first heartbeat is answered.
Future<void> _connect(WidgetTester tester, StreamRoomHarness room) async {
  room.signaling
    ..emit(const VoiceSignalingStatusEvent(VoiceConnectionStatus.ready))
    ..emit(const VoiceTransportReadyEvent(_session))
    ..emit(const VoiceRoundTripEvent(Duration(milliseconds: 24)));
  await tester.pumpAndSettle();
}

Finder _inHeader(Finder matching) =>
    find.descendant(of: find.byType(ChatHeader), matching: matching);

Color? _signalColor(WidgetTester tester) => tester
    .widget<FlucordIcon>(_inHeader(findFlucordIcon(FlucordIcons.signal)))
    .color;

void main() {
  group('header', () {
    testWidgets('names the channel and says it is connected, with the ping', (
      tester,
    ) async {
      final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
      await _connect(tester, room);

      expect(_inHeader(find.text('General')), findsOneWidget);
      expect(_inHeader(find.text('Connected · 24 ms')), findsOneWidget);
      expect(_signalColor(tester), _surfaces.success);
    });

    testWidgets('says what the connection is doing before it is up', (
      tester,
    ) async {
      final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
      room.signaling.emit(
        const VoiceSignalingStatusEvent(VoiceConnectionStatus.connecting),
      );
      await tester.pumpAndSettle();

      expect(_inHeader(find.text('Connecting...')), findsOneWidget);
      expect(_signalColor(tester), _surfaces.muted);
    });

    testWidgets('a channel that is only looked at has no connection state', (
      tester,
    ) async {
      await pumpStreamRoom(tester, streamRoomVoiceChannel, join: false);

      expect(_inHeader(findFlucordIcon(FlucordIcons.signal)), findsNothing);
    });
  });

  group('control row', () {
    testWidgets('runs microphone, deafen, camera, Stream, activities, '
        'soundboard, then hang up', (tester) async {
      await pumpStreamRoom(tester, streamRoomVoiceChannel);

      final controls = find.byType(VoiceRoomControls);
      expect(controls, findsOneWidget);
      double leftOf(Finder control) => tester
          .getTopLeft(find.descendant(of: controls, matching: control).first)
          .dx;
      final order = [
        find.byKey(const ValueKey('voice-mute')),
        find.byKey(const ValueKey('voice-deafen')),
        find.byKey(const ValueKey('voice-camera')),
        find.byKey(const ValueKey('go-live-toggle')),
        find.byKey(const ValueKey('voice-activities')),
        find.byType(SoundboardButton),
        find.byKey(const ValueKey('voice-disconnect')),
      ].map(leftOf).toList();
      expect(order, [...order]..sort());
      expect(order.toSet(), hasLength(order.length));
    });

    testWidgets('a call offers no soundboard on a session without one', (
      tester,
    ) async {
      await pumpStreamRoom(tester, streamRoomCall);

      expect(find.byType(VoiceRoomControls), findsOneWidget);
      // With Nitro it would: dm_call_band_test covers that.
      expect(find.byKey(const ValueKey('soundboard-open')), findsNothing);
    });

    testWidgets('hang up leaves the Room', (tester) async {
      final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);

      await tester.tap(find.byKey(const ValueKey('voice-disconnect')));
      await tester.pumpAndSettle();

      expect(room.voice.isConnected, isFalse);
    });
  });

  group('tiles', () {
    testWidgets('a name chip carries the name and the muted mark', (
      tester,
    ) async {
      await pumpStreamRoom(
        tester,
        streamRoomVoiceChannel,
        seats: const [
          StreamRoomSeat('me'),
          StreamRoomSeat('friend-2', isMuted: true),
        ],
      );

      final mira = _chipOf('friend-2');
      expect(
        find.descendant(of: mira, matching: find.text('Mira')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: mira,
          matching: findFlucordIcon(FlucordIcons.micOff),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _chipOf('me'), matching: find.text('Me (you)')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _chipOf('me'),
          matching: findFlucordIcon(FlucordIcons.micOff),
        ),
        findsNothing,
      );
    });

    testWidgets('whoever speaks gets a green ring around their tile', (
      tester,
    ) async {
      final room = await pumpStreamRoom(
        tester,
        streamRoomVoiceChannel,
        seats: const [StreamRoomSeat('friend-1'), StreamRoomSeat('friend-2')],
      );

      room.signaling.emit(
        const VoiceSpeakingEvent(userId: 'friend-1', ssrc: 7, speakingFlags: 1),
      );
      // One pump delivers the event, the next draws the ring.
      await tester.pump();
      await tester.pump();

      expect(_ringOf(tester, 'friend-1'), _surfaces.success);
      expect(_ringOf(tester, 'friend-2'), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a Stream nobody watches is a tile of its own, live, with '
        'Watch stream', (tester) async {
      await pumpStreamRoom(tester, streamRoomVoiceChannel);

      final stream = find.byKey(const ValueKey('voice-stream-card-friend-1'));
      expect(
        find.byKey(const ValueKey('voice-participant-friend-1')),
        findsOneWidget,
      );
      expect(stream, findsOneWidget);
      expect(
        find.descendant(of: stream, matching: find.text('LIVE')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stream, matching: find.text('Watch stream')),
        findsOneWidget,
      );
      // The person's own tile is not marked: their Stream is right there.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('voice-participant-friend-1')),
          matching: find.text('LIVE'),
        ),
        findsNothing,
      );
    });
  });

  group('stage', () {
    testWidgets('a Stream on the Stage leaves every person in the strip, '
        'its Sender marked live', (tester) async {
      final room = await pumpStreamRoom(
        tester,
        streamRoomVoiceChannel,
        seats: const [
          StreamRoomSeat('friend-1', isStreaming: true),
          StreamRoomSeat('friend-2'),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
      await tester.pump();
      await tester.runAsync(
        () => room.viewer.attach(
          const GoLiveStreamKey.guild(
            guildId: 'guild-1',
            channelId: 'voice-1',
            userId: 'friend-1',
          ),
          packets: const Stream.empty(),
        ),
      );
      await tester.pump();

      final strip = find.byKey(const ValueKey('voice-participant-grid'));
      expect(tester.widget<GridView>(strip).scrollDirection, Axis.horizontal);
      Finder inStrip(String key) =>
          find.descendant(of: strip, matching: find.byKey(ValueKey(key)));
      expect(inStrip('voice-participant-friend-1'), findsOneWidget);
      expect(inStrip('voice-participant-friend-2'), findsOneWidget);
      // The Stream is on the Stage, not in the strip a second time.
      expect(inStrip('voice-stream-card-friend-1'), findsNothing);
      expect(
        find.descendant(
          of: inStrip('voice-participant-friend-1'),
          matching: find.text('LIVE'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('voice-stream-card-friend-1')),
          matching: find.text('Stop watching'),
        ),
        findsOneWidget,
      );
      await tester.runAsync(room.viewer.stop);
      await tester.pump();
    });
  });
}

/// The name chip on [userId]'s person tile.
Finder _chipOf(String userId) => find.descendant(
  of: find.byKey(ValueKey('voice-participant-$userId')),
  matching: find.byKey(const ValueKey('voice-name-chip')),
);

/// The colour of the ring around [userId]'s person tile, or null for none.
Color? _ringOf(WidgetTester tester, String userId) {
  final tile = tester.widget<DecoratedBox>(
    find.byKey(ValueKey('voice-participant-$userId')),
  );
  final border = (tile.decoration as BoxDecoration).border;
  return border?.top.color;
}
