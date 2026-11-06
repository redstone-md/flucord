import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';

import 'support/stream_room_harness.dart';

const _friend = 'friend-1';
const _friendTile = ValueKey('voice-participant-$_friend');

const _session = VoiceTransportSession(
  guildId: 'guild-1',
  ssrc: 1,
  address: '127.0.0.1',
  port: 1000,
  mode: 'aead_aes256_gcm_rtpsize',
  secretKey: [1],
  daveProtocolVersion: 0,
);

/// The voice channel's Room, with its transport up so sound can play.
Future<StreamRoomHarness> _room(
  WidgetTester tester, {
  List<StreamRoomSeat> seats = const [StreamRoomSeat(_friend)],
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final harness = await pumpStreamRoom(
    tester,
    streamRoomVoiceChannel,
    seats: seats,
  );
  harness.signaling.emit(const VoiceTransportReadyEvent(_session));
  await tester.pump();
  return harness;
}

/// Right-clicks the widget [finder] finds, at its centre.
Future<Offset> _rightClick(WidgetTester tester, Finder finder) async {
  final at = tester.getCenter(finder);
  await tester.tapAt(at, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  return at;
}

/// One 20 ms frame of the friend's voice, as the room receives it.
Future<void> _friendSpeaks(
  WidgetTester tester,
  StreamRoomHarness harness,
) async {
  harness.receivedAudio.add(
    VoiceRemotePcmFrame(
      userId: _friend,
      sourceId: _friend,
      samples: Int16List(1920),
    ),
  );
  await tester.pump(VoiceController.speakingHangover);
}

const _rows = [
  'Profile',
  'Message',
  'Mention',
  'User volume',
  'Mute',
  'Mute soundboard',
  'Copy user ID',
];

void main() {
  testWidgets('no tile in the Room carries a slider', (tester) async {
    await _room(tester);

    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('right-clicking a tile opens the participant menu there', (
    tester,
  ) async {
    await _room(tester);

    final at = await _rightClick(tester, find.byKey(_friendTile));

    final tops = [
      for (final row in _rows) tester.getTopLeft(find.text(row)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.text('100%'), findsOneWidget);
    // The menu opens at the pointer, not at the tile's corner.
    final menu = tester.getRect(find.byType(Material).last);
    expect((menu.topLeft - at).distance, lessThan(24));
  });

  testWidgets('dragging the slider sets the level the friend plays at', (
    tester,
  ) async {
    final harness = await _room(tester);
    await _rightClick(tester, find.byKey(_friendTile));

    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pumpAndSettle();

    expect(find.text('200%'), findsOneWidget);
    expect(harness.voice.volumeFor(_friend), 2);
    await _friendSpeaks(tester, harness);
    expect(harness.audio.playing.single.volume, 2);
  });

  testWidgets('Mute silences the friend, marks the tile, and comes back', (
    tester,
  ) async {
    final harness = await _room(tester);
    await harness.voice.setParticipantVolume(_friend, 1.5);
    await _rightClick(tester, find.byKey(_friendTile));

    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();
    await _friendSpeaks(tester, harness);

    expect(harness.voice.isParticipantMuted(_friend), isTrue);
    expect(harness.audio.playing.single.volume, 0);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Muted for you'), findsOneWidget);

    await _rightClick(tester, find.byKey(_friendTile));
    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();

    expect(harness.audio.playing.single.volume, 1.5);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Muted for you'), findsNothing);
  });

  testWidgets('Mute soundboard leaves the voice alone', (tester) async {
    final harness = await _room(tester);
    await _rightClick(tester, find.byKey(_friendTile));

    await tester.tap(find.text('Mute soundboard'));
    await tester.pumpAndSettle();
    await _friendSpeaks(tester, harness);

    expect(harness.voice.isSoundboardMuted(_friend), isTrue);
    expect(harness.voice.isParticipantMuted(_friend), isFalse);
    expect(harness.audio.playing.single.volume, 1);
  });

  testWidgets('this account\'s own tile offers no volume or mute', (
    tester,
  ) async {
    await _room(tester, seats: const [StreamRoomSeat('me')]);

    await _rightClick(
      tester,
      find.byKey(const ValueKey('voice-participant-me')),
    );

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Copy user ID'), findsOneWidget);
    expect(find.text('User volume'), findsNothing);
    expect(find.text('Mute'), findsNothing);
    expect(find.text('Mute soundboard'), findsNothing);
  });

  testWidgets('a tile on the Stage opens the same menu', (tester) async {
    final harness = await _room(tester);
    harness.focus.focus(_friend);
    await tester.pumpAndSettle();

    await _rightClick(tester, find.byKey(const ValueKey('voice-stage-tile')));

    for (final row in _rows) {
      expect(find.text(row), findsOneWidget);
    }
  });

  for (final key in [
    const SingleActivator(LogicalKeyboardKey.contextMenu),
    const SingleActivator(LogicalKeyboardKey.f10, shift: true),
  ]) {
    testWidgets('${key.trigger.keyLabel} opens the menu on a focused tile', (
      tester,
    ) async {
      await _room(tester);
      Focus.of(tester.element(find.byKey(_friendTile))).requestFocus();
      await tester.pump();

      if (key.shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(key.trigger);
      if (key.shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();

      expect(find.text('User volume'), findsOneWidget);
    });
  }

  testWidgets('Mention puts the friend in the channel\'s composer', (
    tester,
  ) async {
    await _room(tester);
    await _rightClick(tester, find.byKey(_friendTile));

    await tester.tap(find.text('Mention'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(MessageComposer),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, '<@$_friend> ');
  });

  testWidgets('Copy user ID puts the id on the clipboard', (tester) async {
    await _room(tester);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _rightClick(tester, find.byKey(_friendTile));

    await tester.tap(find.text('Copy user ID'));
    await tester.pumpAndSettle();

    expect(copied, [_friend]);
    expect(find.text('User volume'), findsNothing);
  });
}
