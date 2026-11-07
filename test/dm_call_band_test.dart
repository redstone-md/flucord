import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/account_entitlements_controller.dart';
import 'package:flucord/src/application/soundboard_controller.dart';
import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/account_entitlements.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/domain/soundboard.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/go_live_viewer.dart';
import 'package:flucord/src/presentation/widgets/voice_participant_grid.dart';
import 'package:flucord/src/theme/flucord_icons.dart';

import 'support/fake_expression_repository.dart';
import 'support/flucord_icon_finder.dart';
import 'support/stream_room_harness.dart';

/// The band is everything above the messages in a DM call.
Finder _inBand(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey('call-band')),
  matching: matching,
);

/// The person [userId] in the band: their avatar, name and caption.
Finder _person(String userId) => find.byKey(ValueKey('call-band-$userId'));

Future<StreamRoomHarness> _pumpCall(
  WidgetTester tester, {
  List<StreamRoomSeat> seats = const [StreamRoomSeat('friend-1')],
  bool join = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  return pumpStreamRoom(tester, streamRoomCall, seats: seats, join: join);
}

/// The call's connection comes up.
Future<void> _connect(WidgetTester tester, StreamRoomHarness call) async {
  call.signaling
    ..emit(const VoiceSignalingStatusEvent(VoiceConnectionStatus.ready))
    ..emit(const VoiceTransportReadyEvent(streamRoomTransport));
  await tester.pumpAndSettle();
}

void main() {
  group('soundboard', _soundboardInCalls);

  testWidgets('a DM call sits above the messages, and the composer stays', (
    tester,
  ) async {
    await _pumpCall(tester);

    final band = tester.getRect(find.byKey(const ValueKey('call-band')));
    final composer = tester.getRect(
      find.byKey(const ValueKey('message-composer')),
    );
    expect(band.bottom, lessThanOrEqualTo(composer.top));
    // A band, not the Room: no tile grid, and no switch between the two.
    expect(find.byType(VoiceParticipantGrid), findsNothing);
    expect(find.byKey(const ValueKey('voice-surface-room')), findsNothing);
    expect(_inBand(find.byKey(const ValueKey('voice-mute'))), findsOneWidget);
    expect(_inBand(find.text('Jack')), findsOneWidget);
    expect(_person('me'), findsOneWidget);
  });

  testWidgets('the band says it is connected, and for how long', (
    tester,
  ) async {
    final call = await _pumpCall(tester);
    await _connect(tester, call);
    await tester.pump(const Duration(seconds: 65));

    expect(_inBand(find.text('Connected · 1:05')), findsOneWidget);
    // It keeps counting.
    await tester.pump(const Duration(seconds: 1));
    expect(_inBand(find.text('Connected · 1:06')), findsOneWidget);
  });

  testWidgets('before the connection is up, the band says what it is doing', (
    tester,
  ) async {
    final call = await _pumpCall(tester);
    call.signaling.emit(
      const VoiceSignalingStatusEvent(VoiceConnectionStatus.connecting),
    );
    await tester.pumpAndSettle();

    expect(_inBand(find.text('Connecting...')), findsOneWidget);
  });

  testWidgets('whoever speaks gets a green ring, a muted person a red badge', (
    tester,
  ) async {
    final call = await _pumpCall(
      tester,
      seats: const [
        StreamRoomSeat('friend-1'),
        StreamRoomSeat('me', isMuted: true),
      ],
    );

    call.signaling.emit(
      const VoiceSpeakingEvent(userId: 'friend-1', ssrc: 7, speakingFlags: 1),
    );
    // One pump delivers the event, the next draws the ring.
    await tester.pump();
    await tester.pump();

    expect(_speaking('friend-1'), findsOneWidget);
    expect(_speaking('me'), findsNothing);
    expect(_mutedBadge('me'), findsOneWidget);
    expect(_mutedBadge('friend-1'), findsNothing);
    expect(_inPerson('friend-1', find.text('Jack')), findsOneWidget);
    expect(_inPerson('me', find.text('Me')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_speaking('friend-1'), findsNothing);
  });

  testWidgets('ringing says who is called, until they walk in', (tester) async {
    final call = await _pumpCall(tester, seats: const [], join: false);

    await call.calls.placeCall('dm-1');
    await tester.pumpAndSettle();

    expect(_inBand(find.text('Calling Jack')), findsOneWidget);
    expect(_inPerson('friend-1', find.text('Ringing')), findsOneWidget);
    expect(_ringing('friend-1'), findsOneWidget);
    expect(_dimmed('friend-1'), findsOneWidget);
    expect(_inPerson('me', find.text('You')), findsOneWidget);

    const jack = VoiceParticipantStateEvent(
      userId: 'friend-1',
      guildId: null,
      channelId: 'dm-1',
      selfMuted: false,
      selfDeafened: false,
      serverMuted: false,
      serverDeafened: false,
      isStreaming: false,
      isVideoEnabled: false,
    );
    call.signaling.seated = {
      'dm-1': [jack],
    };
    call.signaling.emit(jack);
    await tester.pumpAndSettle();

    expect(_inBand(find.text('Calling Jack')), findsNothing);
    expect(find.text('Ringing'), findsNothing);
    expect(_ringing('friend-1'), findsNothing);
    expect(_dimmed('friend-1'), findsNothing);
    expect(find.text('You'), findsNothing);
  });

  testWidgets('a right click on an avatar opens the participant menu', (
    tester,
  ) async {
    final call = await _pumpCall(tester);

    await tester.tap(_person('friend-1'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('participant-menu-volume')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('participant-menu-mute')));
    await tester.pumpAndSettle();
    expect(call.voice.isParticipantMuted('friend-1'), isTrue);

    // Muted for this client shows on the avatar, as on a Room tile.
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    expect(
      _inPerson('friend-1', findFlucordIcon(FlucordIcons.volumeOff)),
      findsOneWidget,
    );
  });

  testWidgets('a right click on a Stream tile opens the Stream menu', (
    tester,
  ) async {
    await _pumpCall(
      tester,
      seats: const [StreamRoomSeat('friend-1', isStreaming: true)],
    );

    await tester.tap(
      _inBand(find.byKey(const ValueKey('voice-stream-card-friend-1'))),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('stream-menu-volume')), findsOneWidget);
    expect(find.byKey(const ValueKey('stream-menu-watch')), findsOneWidget);
    expect(find.byKey(const ValueKey('participant-menu-volume')), findsNothing);
  });

  testWidgets('a Stream is a tile in the band, and watched it sits between '
      'the band and the messages', (tester) async {
    final call = await _pumpCall(
      tester,
      seats: const [StreamRoomSeat('friend-1', isStreaming: true)],
    );
    const key = GoLiveStreamKey.call(channelId: 'dm-1', userId: 'friend-1');

    await tester.tap(
      _inBand(find.byKey(const ValueKey('voice-watch-friend-1'))),
    );
    await tester.pump();
    expect(call.repository.watched, [key]);
    await tester.runAsync(
      () => call.viewer.attach(key, packets: const Stream.empty()),
    );
    // Not settled: the Stage keeps a spinner up until the first picture.
    await tester.pump();

    final band = tester.getRect(find.byKey(const ValueKey('call-band')));
    final stage = tester.getRect(find.byType(GoLiveViewer));
    final composer = tester.getRect(
      find.byKey(const ValueKey('message-composer')),
    );
    expect(stage.top, greaterThanOrEqualTo(band.bottom));
    expect(stage.bottom, lessThanOrEqualTo(composer.top));

    await tester.runAsync(call.viewer.stop);
    await tester.pump();
    expect(find.byType(GoLiveViewer), findsNothing);
    expect(_inBand(find.text('Watch stream')), findsOneWidget);
  });
}

Finder _inPerson(String userId, Finder matching) =>
    find.descendant(of: _person(userId), matching: matching);

Finder _speaking(String userId) =>
    _inPerson(userId, find.byKey(const ValueKey('call-band-speaking')));

Finder _mutedBadge(String userId) =>
    _inPerson(userId, findFlucordIcon(FlucordIcons.micOff));

Finder _ringing(String userId) =>
    _inPerson(userId, find.byKey(const ValueKey('call-band-ringing')));

Finder _dimmed(String userId) =>
    _inPerson(userId, find.byKey(const ValueKey('call-band-away')));

/// What Discord offers in a call: the soundboard needs Nitro there.
void _soundboardInCalls() {
  Future<FakeSoundboardRepository> pumpWith(
    WidgetTester tester,
    PremiumTier tier,
  ) async {
    final repository = FakeSoundboardRepository()
      ..defaults = const [SoundboardSound(id: '3', name: 'quack')]
      ..byGuild['guild-1'] = const [
        SoundboardSound(id: '20', name: 'drum roll', guildId: 'guild-1'),
      ];
    final entitlements = AccountEntitlementsController(
      () => _Entitlements(tier),
    );
    await tester.runAsync(entitlements.load);
    final soundboard = SoundboardController(
      () => repository,
      entitlements: entitlements,
    );
    addTearDown(soundboard.dispose);
    addTearDown(entitlements.dispose);
    addTearDown(repository.close);
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpStreamRoom(
      tester,
      streamRoomCall,
      seats: const [StreamRoomSeat('friend-1')],
      soundboard: soundboard,
    );
    return repository;
  }

  testWidgets('without Nitro a call has no soundboard', (tester) async {
    await pumpWith(tester, PremiumTier.nitroBasic);

    expect(find.byKey(const ValueKey('soundboard-open')), findsNothing);
  });

  testWidgets('with Nitro a server sound plays into the DM call', (
    tester,
  ) async {
    final repository = await pumpWith(tester, PremiumTier.nitro);

    await tester.tap(_inBand(find.byKey(const ValueKey('soundboard-open'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('soundboard-sound-20')));
    await tester.pumpAndSettle();

    final (channelId, sound) = repository.played.single;
    expect(channelId, streamRoomCall.id);
    expect(sound.guildId, 'guild-1');
  });
}

final class _Entitlements implements AccountEntitlementsRepository {
  _Entitlements(this.tier);

  final PremiumTier tier;

  @override
  Future<AccountEntitlements> loadEntitlements() async =>
      AccountEntitlements(premiumTier: tier);
}
