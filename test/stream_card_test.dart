import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/application/stream_viewer_controller.dart';
import 'package:flucord/src/domain/go_live_stream.dart';

import 'support/stream_room_harness.dart';

/// The card is how a stream is discovered, so these are the five things that
/// make it one: it is there, it says whose stream it is, it opens the stream,
/// it closes it again, and it is not there for somebody who is not sending
/// anything. Both kinds of room are covered because a call is a room without a
/// guild, and the card is drawn by the grid both rooms share.
void main() {
  testWidgets('the tile of somebody streaming carries their name', (
    tester,
  ) async {
    await pumpStreamRoom(tester, streamRoomCall);

    // The room header also says "Jack": the channel is the DM with them.
    expect(_onCard('friend-1', find.text('Jack')), findsOneWidget);
    expect(_onCard('friend-1', find.text('Watch')), findsOneWidget);
  });

  testWidgets('the card is there in a server voice room too', (tester) async {
    await pumpStreamRoom(tester, streamRoomVoiceChannel);

    expect(
      find.byKey(const ValueKey('voice-stream-card-friend-1')),
      findsOneWidget,
    );
    expect(_onCard('friend-1', find.text('Jack')), findsOneWidget);
    expect(_onCard('friend-1', find.text('Watch')), findsOneWidget);
  });

  testWidgets('the button opens the stream in a call', (tester) async {
    final harness = await pumpStreamRoom(tester, streamRoomCall);

    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
    await tester.pumpAndSettle();

    expect(harness.repository.watched, [
      const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'friend-1'),
    ]);
  });

  testWidgets('the button opens the stream in a server voice room', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(tester, streamRoomVoiceChannel);

    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
    await tester.pumpAndSettle();

    expect(harness.repository.watched, [
      const GoLiveStreamKey.guild(
        guildId: 'guild-1',
        channelId: 'voice-1',
        userId: 'friend-1',
      ),
    ]);
  });

  testWidgets('the control reads as stopping, and closes the stream', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(tester, streamRoomCall);

    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
    await tester.pumpAndSettle();

    // The pictures cross a connection Discord only opens when asked for, so
    // the ask is what the control is stopping here.
    expect(_onCard('friend-1', find.text('Stop watching')), findsOneWidget);
    expect(find.text('Watch'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
    await tester.pumpAndSettle();

    // One ask, withdrawn: pressing stop twice would dial a second stream.
    expect(harness.repository.watched, [
      const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'friend-1'),
    ]);
    expect(
      harness.viewer.isOpen(
        const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'friend-1'),
      ),
      isFalse,
    );
    expect(_onCard('friend-1', find.text('Watch')), findsOneWidget);
  });

  testWidgets('whoever is being watched is marked on their tile', (
    tester,
  ) async {
    // Two people streaming, so the marker has to name the right one.
    await pumpStreamRoom(
      tester,
      streamRoomCall,
      seats: const [
        StreamRoomSeat('friend-1', isStreaming: true),
        StreamRoomSeat('friend-2', isStreaming: true),
      ],
    );

    expect(
      find.byKey(const ValueKey('voice-stream-open-friend-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('voice-stream-open-friend-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('voice-stream-open-friend-2')),
      findsNothing,
    );
  });

  testWidgets('a fifth stream is refused, and the room says why', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(
      tester,
      streamRoomCall,
      seats: const [
        StreamRoomSeat('friend-1', isStreaming: true),
        StreamRoomSeat('friend-2', isStreaming: true),
      ],
    );

    // Four sessions already open, none of them this room's: the cap is this
    // client's and not the channel's.
    for (var index = 0; index < maxWatchedStreams; index++) {
      await harness.viewer.requestWatch(
        GoLiveStreamKey.call(channelId: 'other-$index', userId: 'u$index'),
      );
    }
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
    // Pumped, not settled: settling would wait out the notice's own timer.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Four, written out: reading the constant back into the expectation would
    // agree with it whatever it said.
    expect(
      find.text('You can watch up to 4 streams at once. Stop one first.'),
      findsOneWidget,
    );
    // Turned down here, so Discord was never asked for a fifth.
    expect(
      harness.repository.watched,
      isNot(
        contains(
          const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'friend-1'),
        ),
      ),
    );
  });

  testWidgets('every open stream is marked on its tile', (tester) async {
    await pumpStreamRoom(
      tester,
      streamRoomCall,
      seats: const [
        StreamRoomSeat('friend-1', isStreaming: true),
        StreamRoomSeat('friend-2', isStreaming: true),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-2')));
    await tester.pumpAndSettle();

    // Two open at once, and both marked: the mark cannot name one user.
    expect(
      find.byKey(const ValueKey('voice-stream-open-friend-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('voice-stream-open-friend-2')),
      findsOneWidget,
    );
  });

  testWidgets('a participant who is not streaming has no card', (tester) async {
    await pumpStreamRoom(
      tester,
      streamRoomCall,
      seats: const [
        StreamRoomSeat('friend-1', isStreaming: true),
        StreamRoomSeat('friend-2'),
      ],
    );

    expect(find.text('Mira'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voice-stream-card-friend-2')),
      findsNothing,
    );
  });

  testWidgets('the sender tile shows its own picture as live', (tester) async {
    final harness = await pumpStreamRoom(
      tester,
      streamRoomCall,
      seats: const [
        StreamRoomSeat('me'),
        StreamRoomSeat('friend-1', isStreaming: true),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    // The sender tile draws the share's own pictures, decoded locally; no
    // watch goes to Discord for it (ADR-0001).
    expect(harness.selfPreviewDecoder.started, 1);
    expect(harness.repository.watched, isEmpty);
    expect(find.byKey(const ValueKey('voice-self-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('go-live-waiting')), findsOneWidget);
    expect(_onCard('me', find.text('Live')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-stream-open-me')), findsOneWidget);
    await harness.goLive.stop();
  });

  testWidgets('a preview that cannot decode says so instead of a picture', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(
      tester,
      streamRoomCall,
      seats: const [
        StreamRoomSeat('me'),
        StreamRoomSeat('friend-1', isStreaming: true),
      ],
      selfPreviewOpens: false,
    );

    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('voice-self-preview-error')),
      findsOneWidget,
    );
    expect(find.text('Self-preview unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-self-preview')), findsNothing);
    // The share itself is fine.
    expect(_onCard('me', find.text('Live')), findsOneWidget);
    await harness.goLive.stop();
  });

  testWidgets('this account ends its own share from its own tile', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(
      tester,
      streamRoomCall,
      seats: const [
        StreamRoomSeat('me'),
        StreamRoomSeat('friend-1', isStreaming: true),
      ],
    );

    // Not sharing: the tile is an ordinary one, and the room's share button is
    // the only control there is.
    expect(find.byKey(const ValueKey('voice-stream-card-me')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    expect(_onCard('me', find.text('Stop sharing')), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-watch-me')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('voice-stop-share-me')));
    await tester.pumpAndSettle();

    expect(harness.repository.ended, [
      const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'me'),
    ]);
    expect(find.byKey(const ValueKey('voice-stream-card-me')), findsNothing);
  });
}

/// [matching], inside the card on [userId]'s tile.
Finder _onCard(String userId, Finder matching) => find.descendant(
  of: find.byKey(ValueKey('voice-stream-card-$userId')),
  matching: matching,
);
