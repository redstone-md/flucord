import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';

import 'support/stream_room_harness.dart';

const _sender = 'friend-1';
const _key = GoLiveStreamKey.guild(
  guildId: 'guild-1',
  channelId: 'voice-1',
  userId: _sender,
);
const _card = ValueKey('voice-stream-card-$_sender');
const _stage = ValueKey('stage-stream');
const _page = ValueKey('stream-full-screen');

const _session = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 1,
  address: '127.0.0.1',
  port: 1000,
  mode: 'aead_aes256_gcm_rtpsize',
  secretKey: [1],
  daveProtocolVersion: 0,
);

/// The voice channel's Room with the friend streaming, its transport up so
/// sound can play.
Future<StreamRoomHarness> _room(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final harness = await pumpStreamRoom(tester, streamRoomVoiceChannel);
  harness.signaling.emit(const VoiceTransportReadyEvent(_session));
  await tester.pump();
  return harness;
}

/// Lets a menu or a route finish opening. Not settled: the Stage keeps a
/// spinner turning while this silent Stream has no picture.
Future<void> _open(WidgetTester tester) async {
  // The first frame starts the route's animation; the second ends it.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Watches the friend's Stream, which puts it on the Stage.
Future<StreamRoomHarness> _watchedRoom(WidgetTester tester) async {
  final harness = await _room(tester);
  await tester.tap(find.byKey(const ValueKey('voice-watch-$_sender')));
  await tester.pump();
  await tester.runAsync(
    () => harness.viewer.attach(_key, packets: const Stream.empty()),
  );
  await tester.pump();
  expect(find.byKey(_stage), findsOneWidget);
  return harness;
}

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  await tester.tapAt(tester.getCenter(finder), buttons: kSecondaryButton);
  await _open(tester);
}

Future<void> _doubleClick(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(finder);
  await _open(tester);
}

/// Opens full screen from the Stream menu on the Stage.
Future<void> _fullScreenFromMenu(WidgetTester tester) async {
  await _rightClick(tester, find.byKey(_stage));
  await tester.tap(find.text('Full screen'));
  await _open(tester);
}

void main() {
  testWidgets('right-clicking the watched Stage opens the Stream menu', (
    tester,
  ) async {
    await _watchedRoom(tester);

    await _rightClick(tester, find.byKey(_stage));

    const rows = ['Full screen', 'Stream volume', 'Mute stream'];
    final tops = [
      for (final row in [...rows, 'Stop watching'])
        tester.getTopLeft(find.text(row).last).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Pop out'), findsNothing);
  });

  testWidgets('a Stream that is not watched offers Watch stream instead', (
    tester,
  ) async {
    final harness = await _room(tester);

    await _rightClick(tester, find.byKey(_card));

    expect(find.text('Stream volume'), findsOneWidget);
    expect(find.text('Mute stream'), findsOneWidget);
    expect(find.text('Full screen'), findsNothing);
    // The last one is the menu's, over the tile's own button.
    await tester.tap(find.text('Watch stream').last);
    await _open(tester);
    expect(harness.viewer.isOpen(_key), isTrue);
  });

  testWidgets('Stop watching ends the Watched session', (tester) async {
    final harness = await _watchedRoom(tester);

    await _rightClick(tester, find.byKey(_stage));
    await tester.tap(find.byKey(const ValueKey('stream-menu-stop-watching')));
    await _open(tester);

    // The Stage redraws once the connection has closed, which is real async
    // work a fake-async test body cannot wait out.
    expect(harness.viewer.isOpen(_key), isFalse);
    expect(harness.viewer.isWatching(_key), isFalse);
  });

  testWidgets('Stream volume and mute set the sound, not the picture', (
    tester,
  ) async {
    final harness = await _watchedRoom(tester);
    await _rightClick(tester, find.byKey(_stage));

    await tester.drag(find.byType(Slider), const Offset(-1000, 0));
    await tester.pump();
    expect(find.text('0%'), findsOneWidget);
    expect(harness.voice.streamVolumeFor(_sender), 0);
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.tap(find.text('Mute stream'));
    await tester.pump();

    harness.receivedAudio.add(
      VoiceRemotePcmFrame(
        userId: _sender,
        sourceId: _key.audioSourceId(1),
        samples: Int16List(1920),
      ),
    );
    await tester.pump();
    expect(harness.voice.isStreamMuted(_sender), isTrue);
    expect(harness.voice.streamVolumeFor(_sender), 1);
    expect(harness.audio.playing.single.volume, 0);
    expect(harness.viewer.isWatching(_key), isTrue);
  });

  testWidgets('full screen opens from the menu and Esc closes it', (
    tester,
  ) async {
    final harness = await _watchedRoom(tester);
    final before = harness.window.bounds;

    await _fullScreenFromMenu(tester);
    expect(find.byKey(_page), findsOneWidget);
    expect(harness.window.calls, ['enter']);
    // Full screen is a different frame; leaving must not keep it.
    harness.window.bounds = const Rect.fromLTWH(0, 0, 1920, 1080);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _open(tester);

    expect(find.byKey(_page), findsNothing);
    expect(harness.viewer.isWatching(_key), isTrue);
    await tester.runAsync(pumpEventQueue);
    expect(harness.window.calls, [
      'enter',
      'leave',
      'left',
      'setBounds $before',
    ]);
  });

  testWidgets('the Stage button opens full screen, and the same closes it', (
    tester,
  ) async {
    await _watchedRoom(tester);

    await tester.tap(find.byKey(const ValueKey('stage-stream-full-screen')));
    await _open(tester);
    expect(find.byKey(_page), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stream-full-screen-exit')));
    await _open(tester);
    expect(find.byKey(_page), findsNothing);
  });

  testWidgets('a double-click opens full screen, and another closes it', (
    tester,
  ) async {
    await _watchedRoom(tester);

    await _doubleClick(tester, find.byKey(_stage));
    expect(find.byKey(_page), findsOneWidget);

    await _doubleClick(tester, find.byKey(_page));
    expect(find.byKey(_page), findsNothing);
  });

  testWidgets('full screen follows the Watched session, not its pictures', (
    tester,
  ) async {
    final harness = await _room(tester);
    await tester.tap(find.byKey(const ValueKey('voice-watch-$_sender')));
    await tester.pump();
    expect(harness.viewer.isOpen(_key), isTrue);
    expect(harness.viewer.isWatching(_key), isFalse);

    // Asked for, nothing arriving yet: the session is open all the same.
    await _rightClick(tester, find.byKey(_card));
    await tester.tap(find.text('Full screen'));
    await _open(tester);
    expect(find.byKey(_page), findsOneWidget);

    // A reconnect replaces the session; the page stays through it.
    for (var i = 0; i < 2; i++) {
      await tester.runAsync(
        () => harness.viewer.attach(_key, packets: const Stream.empty()),
      );
      await tester.pump();
      expect(find.byKey(_page), findsOneWidget);
    }
  });

  testWidgets('Full screen opens after the Stage that asked has gone', (
    tester,
  ) async {
    final harness = await _watchedRoom(tester);
    await _rightClick(tester, find.byKey(_stage));

    // The Stage leaves while its menu is open; the session stays.
    harness.focus.clear();
    await tester.pump();
    expect(find.byKey(_stage), findsNothing);
    await tester.tap(find.text('Full screen'));
    await _open(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(_page), findsOneWidget);
  });

  testWidgets('full screen closes by itself when the session stops', (
    tester,
  ) async {
    final harness = await _watchedRoom(tester);
    await _fullScreenFromMenu(tester);

    await tester.runAsync(() => harness.viewer.stop(_key));
    await _open(tester);

    expect(find.byKey(_page), findsNothing);
    await tester.runAsync(pumpEventQueue);
    expect(harness.window.calls.first, 'enter');
    expect(harness.window.calls, contains('leave'));
  });

  testWidgets('full screen closes by itself when this account leaves', (
    tester,
  ) async {
    final harness = await _watchedRoom(tester);
    await _fullScreenFromMenu(tester);

    await tester.runAsync(harness.voice.disconnect);
    await settleStreamRoom(tester);
    await _open(tester);

    expect(find.byKey(_page), findsNothing);
  });
}
