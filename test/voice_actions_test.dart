import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/application/voice_controller.dart';

import 'support/flucord_icon_finder.dart';
import 'support/stream_room_harness.dart';

void main() {
  /// A joined room where the push-to-talk key is up, with the next voice
  /// action held open once it has sent its frame.
  Future<(StreamRoomHarness, Completer<void>)> pushToTalkRoom(
    WidgetTester tester,
  ) async {
    final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
    await room.voice.setMuted(muted: true);
    final hold = Completer<void>();
    room.signaling.hold = hold;
    return (room, hold);
  }

  /// Lets the held action finish, and everything queued behind it.
  Future<void> finish(WidgetTester tester, StreamRoomHarness room) async {
    room.signaling.hold?.complete();
    room.signaling.hold = null;
    await tester.pumpAndSettle();
  }

  group('push to talk', () {
    testWidgets('a release during a long action leaves the microphone off', (
      tester,
    ) async {
      final (room, _) = await pushToTalkRoom(tester);

      unawaited(room.voice.setMuted(muted: false));
      await tester.pump();
      unawaited(room.voice.setMuted(muted: true));
      await finish(tester, room);

      expect(room.media.microphoneOn, isFalse);
      expect(room.signaling.frames.last.selfMute, isTrue);
      expect(findFlucordIcon(FlucordIcons.micOff), findsOneWidget);
    });

    testWidgets('a press and release behind a long action stay muted', (
      tester,
    ) async {
      final (room, _) = await pushToTalkRoom(tester);

      // Something else is running when the key goes down and comes up.
      unawaited(room.voice.setCameraAnnounced(enabled: true));
      await tester.pump();
      unawaited(room.voice.setMuted(muted: false));
      unawaited(room.voice.setMuted(muted: true));
      await finish(tester, room);

      expect(room.media.microphoneOn, isFalse);
      expect(room.signaling.frames.last.selfMute, isTrue);
    });

    testWidgets('a release while the devices open is kept once in the Room', (
      tester,
    ) async {
      final room = await pumpStreamRoom(
        tester,
        streamRoomVoiceChannel,
        join: false,
      );
      final opening = Completer<void>();
      room.media.hold = opening;

      unawaited(room.joinRoom());
      await tester.pump();
      unawaited(room.voice.setMuted(muted: true));
      opening.complete();
      await tester.pumpAndSettle();

      expect(room.media.microphoneOn, isFalse);
      expect(room.signaling.frames.last.selfMute, isTrue);
    });

    testWidgets('a release delay that ends during a long action still mutes', (
      tester,
    ) async {
      final (room, _) = await pushToTalkRoom(tester);
      await room.voice.setPushToTalkReleaseDelayMs(100);

      unawaited(room.voice.setMuted(muted: false));
      await tester.pump();
      await room.voice.setMuted(muted: true);
      await tester.pump(const Duration(milliseconds: 150));
      await finish(tester, room);

      expect(room.media.microphoneOn, isFalse);
      expect(room.signaling.frames.last.selfMute, isTrue);
    });
  });

  group('leave', () {
    testWidgets('during a join ends with no Room', (tester) async {
      final room = await pumpStreamRoom(
        tester,
        streamRoomVoiceChannel,
        join: false,
      );
      room.signaling.hold = Completer<void>();

      unawaited(room.joinRoom());
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-disconnect')));
      await tester.pump();
      await finish(tester, room);

      expect(room.signaling.frames.last.channelId, isNull);
      expect(room.media.microphoneOn, isFalse);
      expect(find.byKey(const ValueKey('voice-disconnect')), findsNothing);
    });

    testWidgets('while the devices open sends no join after it', (
      tester,
    ) async {
      final room = await pumpStreamRoom(
        tester,
        streamRoomVoiceChannel,
        join: false,
      );
      final opening = Completer<void>();
      room.media.hold = opening;

      unawaited(room.joinRoom());
      await tester.pump();
      unawaited(room.voice.disconnect());
      await tester.pump();
      opening.complete();
      await tester.pumpAndSettle();

      expect(room.signaling.frames.lastOrNull?.channelId, isNull);
      expect(room.media.microphoneOn, isFalse);
      expect(find.byKey(const ValueKey('voice-disconnect')), findsNothing);
    });

    testWidgets('in flight keeps a camera press from rejoining the channel', (
      tester,
    ) async {
      final room = await pumpStreamRoom(tester, streamRoomVoiceChannel);
      room.signaling.hold = Completer<void>();

      unawaited(room.voice.disconnect());
      await tester.pump();
      final announced = room.voice.setCameraAnnounced(enabled: true);
      await tester.pump();
      await finish(tester, room);

      expect(await announced, isFalse);
      expect(room.signaling.frames.last.channelId, isNull);
    });
  });

  testWidgets('a second join during a join sends one', (tester) async {
    final room = await pumpStreamRoom(
      tester,
      streamRoomVoiceChannel,
      join: false,
    );
    room.signaling.hold = Completer<void>();

    unawaited(room.joinRoom());
    await tester.pump();
    unawaited(room.joinRoom());
    await tester.pump();
    await finish(tester, room);

    expect(room.signaling.frames, hasLength(1));
  });

  testWidgets('mute works from the room during a long action', (tester) async {
    final (room, _) = await pushToTalkRoom(tester);

    unawaited(room.voice.setMuted(muted: false));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voice-mute')));
    await tester.pump();

    // The new choice shows at once and reaches Discord when its turn comes.
    expect(findFlucordIcon(FlucordIcons.micOff), findsOneWidget);
    await finish(tester, room);
    expect(room.signaling.frames.last.selfMute, isTrue);
    expect(room.media.microphoneOn, isFalse);
  });
}
