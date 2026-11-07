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
    VoiceConnectionStatus.ready: 'Connected',
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

  testWidgets('a Room whose connection failed offers to try again', (
    tester,
  ) async {
    final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
    await _say(tester, room, VoiceConnectionStatus.failure);
    room.signaling.frames.clear();

    await tester.tap(find.byKey(const ValueKey('voice-room-retry-connection')));
    await tester.pumpAndSettle();

    expect(room.signaling.frames.single.channelId, 'voice-1');
    expect(find.text('Joining voice channel...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voice-room-retry-connection')),
      findsNothing,
    );
  });

  testWidgets('a Room that is connected or reconnecting offers no retry', (
    tester,
  ) async {
    final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
    for (final status in [
      VoiceConnectionStatus.ready,
      VoiceConnectionStatus.reconnecting,
    ]) {
      await _say(tester, room, status);

      expect(
        find.byKey(const ValueKey('voice-room-retry-connection')),
        findsNothing,
        reason: '$status',
      );
    }
  });

  // Muted and deafened show on the control row's buttons, so the header
  // keeps saying the connection is up.
  testWidgets('a muted Room still says it is connected', (tester) async {
    final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
    await _say(tester, room, VoiceConnectionStatus.ready);

    await tester.tap(find.byKey(const ValueKey('voice-mute')));
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOneWidget);
    expect(find.byTooltip('Unmute'), findsOneWidget);
  });

  testWidgets('a server mute and deafen have their own mark, and the own '
      'buttons still toggle', (tester) async {
    final room = await pumpStreamRoom(
      tester,
      streamRoomVoiceChannel,
      seats: const [
        StreamRoomSeat('me', isServerMuted: true, isServerDeafened: true),
      ],
    );
    room.signaling.emit(
      const VoiceCredentialsReadyEvent(
        VoiceServerCredentials(
          guildId: 'guild-1',
          channelId: 'voice-1',
          userId: 'me',
          sessionId: 'session-1',
          token: 'token',
          endpoint: 'voice.discord.gg',
        ),
      ),
    );
    await _say(tester, room, VoiceConnectionStatus.ready);

    expect(find.byTooltip('Server muted · Mute'), findsOneWidget);
    expect(find.byTooltip('Server deafened · Deafen'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-mute')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-deafen')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Server muted · Unmute'), findsOneWidget);
    expect(find.byTooltip('Server deafened · Undeafen'), findsOneWidget);
  });

  testWidgets('a deafened Room still says it is connected', (tester) async {
    final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
    await _say(tester, room, VoiceConnectionStatus.ready);

    await tester.tap(find.byKey(const ValueKey('voice-deafen')));
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOneWidget);
    expect(find.byTooltip('Undeafen'), findsOneWidget);
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
