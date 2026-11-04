part of 'presence_widget_test.dart';

void _memberPanelCases() {
  group('member panel', () {
    Widget sidebar() => _host(
      Row(
        children: [
          const Expanded(child: SizedBox()),
          MemberSidebar(
            members: [
              _member(
                _mira,
                'Mira Chen',
                presence: const UserPresence(
                  status: Presence.online,
                  activities: [_game],
                ),
              ),
              _member(
                _roman,
                'Roman Vale',
                presence: const UserPresence(status: Presence.offline),
              ),
            ],
            spaceId: 'guild-1',
            cardFor: (member, _) => MemberProfileCard(
              member: member,
              spaceId: 'guild-1',
              now: _now,
            ),
          ),
        ],
      ),
    );

    testWidgets('a row shows the activity in place of the role', (
      tester,
    ) async {
      await tester.pumpWidget(sidebar());

      expect(
        find.byKey(const ValueKey('member-activity-$_mira')),
        findsOneWidget,
      );
      expect(find.text('Elden Ring'), findsOneWidget);
      // Nothing to show is no second line: the role is never the fallback.
      expect(
        find.byKey(const ValueKey('member-activity-$_roman')),
        findsNothing,
      );
      expect(find.text('Engineer'), findsNothing);
    });

    testWidgets('the profile popover carries the rich presence card', (
      tester,
    ) async {
      await tester.pumpWidget(sidebar());

      await tester.tap(find.byKey(const ValueKey('member-row-$_mira')));
      await tester.pump();

      expect(find.byKey(const ValueKey('activity-card')), findsOneWidget);
      expect(find.text('Playing'), findsOneWidget);
      expect(find.text('Limgrave'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('labels the card for the activity type it shows', (
      tester,
    ) async {
      const labels = {
        ActivityType.playing: 'Playing',
        ActivityType.streaming: 'Streaming',
        ActivityType.listening: 'Listening to',
        ActivityType.watching: 'Watching',
        ActivityType.competing: 'Competing in',
        ActivityType.unrecognised: 'Activity',
      };
      for (final entry in labels.entries) {
        await tester.pumpWidget(
          _host(
            Center(
              child: MemberProfileCard(
                member: _member(
                  _mira,
                  'Mira Chen',
                  presence: UserPresence(
                    status: Presence.online,
                    activities: [
                      _custom,
                      UserActivity(
                        name: 'Something',
                        type: entry.key,
                        details: 'Chapter 3',
                      ),
                    ],
                  ),
                ),
                spaceId: 'guild-1',
                now: _now,
              ),
            ),
          ),
        );

        expect(find.text(entry.value), findsOneWidget);
        // The custom status sits in the bubble beside the avatar.
        expect(find.text('Heads down'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the roster and popover fit a compact window', (tester) async {
      tester.view
        ..physicalSize = const Size(480, 560)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(sidebar());
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('member-row-$_mira')));
      await tester.pump();

      expect(find.byKey(const ValueKey('profile-card')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
