import 'package:flucord/src/presentation/widgets/guild_scheduled_events_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _event = GuildScheduledEvent(
  id: '222222222222222222',
  spaceId: '111111111111111111',
  name: 'Forge night',
  scheduledStartTime: DateTime.utc(2026, 8, 1, 18),
  entityType: GuildScheduledEventEntityType.external,
  status: GuildScheduledEventStatus.scheduled,
  location: 'The workshop',
  interestedCount: 3,
);

void main() {
  group('the button', () {
    testWidgets('says interested, then says it can be taken back', (
      tester,
    ) async {
      final asked = <bool>[];
      await _pumpDialog(
        tester,
        onSetInterest: (event, {required interested}) async {
          asked.add(interested);
          return true;
        },
      );

      final button = find.byKey(ValueKey('guild-event-interest-${_event.id}'));
      expect(button, findsOneWidget);
      expect(find.text('Interested'), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(asked, [true]);
      expect(find.text('Not interested'), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(asked, [true, false]);
      expect(find.text('Interested'), findsOneWidget);
    });

    testWidgets('a refusal puts the label back', (tester) async {
      await _pumpDialog(
        tester,
        onSetInterest: (event, {required interested}) async => false,
      );

      await tester.tap(
        find.byKey(ValueKey('guild-event-interest-${_event.id}')),
      );
      await tester.pumpAndSettle();

      // An event that has ended is refused; claiming an RSVP that was never
      // recorded would be worse than flipping back.
      expect(find.text('Interested'), findsOneWidget);
    });

    testWidgets('the count is left to the dispatch that moves it', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        onSetInterest: (event, {required interested}) async => true,
      );

      await tester.tap(
        find.byKey(ValueKey('guild-event-interest-${_event.id}')),
      );
      await tester.pumpAndSettle();

      // Still three: two places counting the same thing is how a count ends
      // up permanently wrong by one.
      expect(find.text('3 interested'), findsOneWidget);
    });

    testWidgets('the count opens the list of who is coming', (tester) async {
      final asked = <String>[];
      await _pumpDialog(
        tester,
        onShowAttendees: (event) => asked.add(event.id),
      );

      await tester.tap(find.byKey(ValueKey('guild-event-who-${_event.id}')));
      await tester.pumpAndSettle();

      expect(asked, [_event.id]);
    });

    testWidgets('the names appear once they have arrived', (tester) async {
      await _pumpDialog(
        tester,
        onShowAttendees: (_) {},
        attendees: const [
          GuildScheduledEventAttendee(userId: 'user-1', displayName: 'Mira'),
          GuildScheduledEventAttendee(userId: 'user-2'),
        ],
      );

      expect(
        find.byKey(ValueKey('guild-event-attendees-${_event.id}')),
        findsOneWidget,
      );
      // Somebody Discord named nothing for still reads as a person, by id.
      expect(find.text('Mira, user-2'), findsOneWidget);
    });

    testWidgets('a transport that cannot answer shows a plain count', (
      tester,
    ) async {
      await _pumpDialog(tester);

      expect(
        find.byKey(ValueKey('guild-event-who-${_event.id}')),
        findsNothing,
      );
      expect(find.text('3 interested'), findsOneWidget);
    });

    testWidgets('a transport that cannot say offers no control', (
      tester,
    ) async {
      await _pumpDialog(tester);

      expect(
        find.byKey(ValueKey('guild-event-interest-${_event.id}')),
        findsNothing,
      );
      expect(find.text('3 interested'), findsOneWidget);
    });
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  Future<bool> Function(GuildScheduledEvent, {required bool interested})?
  onSetInterest,
  void Function(GuildScheduledEvent)? onShowAttendees,
  List<GuildScheduledEventAttendee> attendees = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: GuildScheduledEventsDialog(
          space: const CommunitySpace(
            id: '111111111111111111',
            name: 'The Forge',
            monogram: 'TF',
            colorValue: 0xff456b5a,
          ),
          workspace: _workspace,
          events: [_event],
          isLoading: false,
          error: null,
          onRefresh: () {},
          onSetInterest: onSetInterest,
          onShowAttendees: onShowAttendees,
          attendeesFor: (_) => attendees,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: '111111111111111111',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [],
  members: const [],
  messages: const [],
  currentMemberId: 'current-user',
);
