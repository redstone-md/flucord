import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flucord/src/presentation/widgets/go_live_viewer.dart';
import 'package:flucord/src/presentation/widgets/voice_participant_grid.dart';
import 'package:flucord/src/presentation/widgets/voice_room_view.dart';

import 'support/stream_room_harness.dart';

/// A call is a room without a guild, and these are the controls a server voice
/// room already had. The one thing that could go wrong is the key: a stream is
/// addressed by room and sender, so a room that passed the DM pseudo-space as
/// a guild would ask Discord for a server no account is in.
void main() {
  testWidgets('a call room offers the stream somebody else is sending', (
    tester,
  ) async {
    await pumpStreamRoom(tester, streamRoomCall);

    expect(find.byType(VoiceRoomView), findsOneWidget);
    expect(find.byKey(const ValueKey('go-live-toggle')), findsOneWidget);
    // The icon alone was all a call used to show.
    expect(find.byKey(const ValueKey('voice-watch-friend-1')), findsOneWidget);
  });

  testWidgets('opening a stream in a call asks for a call stream key', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(tester, streamRoomCall);

    await tester.tap(find.byKey(const ValueKey('voice-watch-friend-1')));
    await tester.pumpAndSettle();

    expect(harness.repository.watched, [
      const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'friend-1'),
    ]);
  });

  testWidgets('this account sends a stream in a call, and stops', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(tester, streamRoomCall);

    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    // No guild in the create frame: the room is a call, and Discord answers a
    // guild-flavoured create for a call with a stream nobody can open.
    expect(harness.repository.startedGuildIds, [null]);
    expect(harness.repository.startedChannels, ['dm-1']);

    await tester.tap(find.byKey(const ValueKey('go-live-toggle')));
    await tester.pumpAndSettle();

    expect(harness.repository.ended, [
      const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'me'),
    ]);
  });

  testWidgets('the stream takes the stage, and the tiles stay under it', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(tester, streamRoomCall);

    await tester.runAsync(
      () => harness.viewer.attach(
        const GoLiveStreamKey.call(channelId: 'dm-1', userId: 'friend-1'),
        packets: const Stream.empty(),
      ),
    );
    // Not settled: the stage keeps a spinner up until the first picture
    // arrives, and this stream is deliberately silent.
    await tester.pump();

    expect(find.byType(GoLiveViewer), findsOneWidget);
    // A tile is where the mark and the control for that stream live, so the
    // stage shrinks the grid into a strip rather than dropping it.
    expect(find.byType(VoiceParticipantGrid), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voice-on-stage-friend-1')),
      findsOneWidget,
    );
    expect(find.text('Stop watching'), findsOneWidget);

    // Cancelling the packet subscription is real async work, which a
    // fake-async test body cannot wait out.
    await tester.runAsync(harness.viewer.stop);
    await tester.pump();

    expect(find.byType(GoLiveViewer), findsNothing);
    expect(find.byType(VoiceParticipantGrid), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voice-on-stage-friend-1')),
      findsNothing,
    );
    expect(find.text('Watch'), findsOneWidget);
  });

  testWidgets('a server voice room still asks for a guild stream key', (
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

  testWidgets('a server voice room joins as a guild room, not as a call', (
    tester,
  ) async {
    final harness = await pumpStreamRoom(
      tester,
      streamRoomVoiceChannel,
      join: false,
    );

    await tester.tap(find.byKey(const ValueKey('voice-channel-join')));
    await tester.pumpAndSettle();

    // The join is the half the stream key cannot cover: the key comes off the
    // channel, so it would still be right on a room that had joined as a
    // call, and only the request Discord gets would be wrong.
    expect(harness.voice.connectedGuildId, 'guild-1');
    expect(harness.voice.isCallSession, isFalse);
  });
}
