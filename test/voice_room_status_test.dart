import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/voice_connection.dart';

import 'support/stream_room_harness.dart';

/// Words that describe how voice works and not what the person can do.
final _internals = RegExp(r'transport|udp|dave|encrypt', caseSensitive: false);

void main() {
  const says = {
    VoiceConnectionStatus.joining: 'Joining voice channel...',
    VoiceConnectionStatus.connecting: 'Connecting...',
    VoiceConnectionStatus.discovering: 'Connecting...',
    VoiceConnectionStatus.negotiating: 'Connecting...',
    VoiceConnectionStatus.ready: 'Voice connected',
    VoiceConnectionStatus.reconnecting: 'Reconnecting...',
    VoiceConnectionStatus.failure: 'Could not connect',
    VoiceConnectionStatus.disconnected: 'Disconnected',
  };

  for (final MapEntry(key: status, value: words) in says.entries) {
    testWidgets('the Room says "$words" while ${status.name}', (tester) async {
      final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);

      await _say(tester, room, status);

      expect(find.text(words), findsOneWidget);
      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>();
      expect(shown.where(_internals.hasMatch), isEmpty);
    });
  }

  testWidgets('a muted Room says it is muted', (tester) async {
    final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
    await _say(tester, room, VoiceConnectionStatus.ready);

    await tester.tap(find.byKey(const ValueKey('voice-mute')));
    await tester.pumpAndSettle();

    expect(find.text('Voice connected, muted'), findsOneWidget);
  });

  testWidgets('a deafened Room says it is deafened', (tester) async {
    final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
    await _say(tester, room, VoiceConnectionStatus.ready);

    await tester.tap(find.byKey(const ValueKey('voice-deafen')));
    await tester.pumpAndSettle();

    expect(find.text('Voice connected, deafened'), findsOneWidget);
  });
}

Future<void> _say(
  WidgetTester tester,
  StreamRoomHarness room,
  VoiceConnectionStatus status,
) async {
  room.signaling.emit(VoiceSignalingStatusEvent(status));
  await tester.pumpAndSettle();
}
