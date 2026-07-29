import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/voice_connection.dart';
import 'package:flucord/src/presentation/widgets/voice_participant_grid.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('renders profiles, speaking state, and unknown fallback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(760, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _TestApp(
        participants: const [
          VoiceParticipant(userId: 'member-1', speakingFlags: 1),
          VoiceParticipant(userId: 'missing-123456', selfMuted: true),
        ],
      ),
    );

    expect(find.text('Jack'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Unknown user 123456'), findsOneWidget);
    expect(find.byTooltip('Muted'), findsOneWidget);
    final tile = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('voice-participant-member-1')),
    );
    final decoration = tile.decoration as BoxDecoration;
    expect(decoration.border!.top.color, FlucordColors.success);
    expect(decoration.border!.top.width, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at compact width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(300, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const _TestApp(
        participants: [
          VoiceParticipant(
            userId: 'member-1',
            selfDeafened: true,
            isStreaming: true,
          ),
        ],
      ),
    );

    expect(
      find.byKey(const ValueKey('voice-participant-grid')),
      findsOneWidget,
    );
    expect(find.byTooltip('Streaming'), findsOneWidget);
    expect(find.byTooltip('Deafened'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a share can be opened and closed from the tile', (tester) async {
    final watched = <String>[];
    const participant = VoiceParticipant(userId: 'member-2', isStreaming: true);
    await tester.pumpWidget(
      _TestApp(participants: const [participant], onWatchStream: watched.add),
    );

    // The icon alone was all there was: the pictures cross a connection
    // Discord only opens when asked, so there has to be something to ask with.
    await tester.tap(find.byKey(const ValueKey('voice-watch-member-2')));
    await tester.pumpAndSettle();

    expect(watched, ['member-2']);

    await tester.pumpWidget(
      _TestApp(
        participants: const [participant],
        onWatchStream: watched.add,
        watchedUserId: 'member-2',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Stop watching'), findsOneWidget);
  });

  testWidgets('this account is not offered its own share', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        participants: const [
          VoiceParticipant(userId: 'member-1', isStreaming: true),
        ],
        onWatchStream: (_) {},
      ),
    );

    expect(find.byKey(const ValueKey('voice-watch-member-1')), findsNothing);
    expect(find.byTooltip('Streaming'), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.participants,
    this.onWatchStream,
    this.watchedUserId,
  });

  final List<VoiceParticipant> participants;
  final void Function(String userId)? onWatchStream;
  final String? watchedUserId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: VoiceParticipantGrid(
          participants: participants,
          members: const [
            Member(
              id: 'member-1',
              displayName: 'Jack',
              initials: 'JK',
              role: 'Operator',
              presence: Presence.online,
              colorValue: 0xff4c9b72,
            ),
          ],
          currentMemberId: 'member-1',
          spaceId: 'guild-1',
          onWatchStream: onWatchStream,
          watchedUserId: watchedUserId,
        ),
      ),
    );
  }
}
