import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

    testWidgets('a call has no soundboard', (tester) async {
      await pumpStreamRoom(tester, streamRoomCall);

      expect(find.byType(VoiceRoomControls), findsOneWidget);
      expect(find.byType(SoundboardButton), findsNothing);
    });

    testWidgets('hang up leaves the Room', (tester) async {
      final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);

      await tester.tap(find.byKey(const ValueKey('voice-disconnect')));
      await tester.pumpAndSettle();

      expect(room.voice.isConnected, isFalse);
    });
  });
}
