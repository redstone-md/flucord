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
            currentMemberId: _me,
            onMessage: (_) {},
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
      expect(find.text('Playing Elden Ring'), findsOneWidget);
      // The offline member keeps its role line.
      expect(find.text('Engineer'), findsOneWidget);
    });

    testWidgets('the profile popover carries the rich presence card', (
      tester,
    ) async {
      await tester.pumpWidget(sidebar());

      await tester.tap(find.byKey(const ValueKey('member-row-$_mira')));
      await tester.pump();

      expect(find.byKey(const ValueKey('activity-card')), findsOneWidget);
      expect(find.text('PLAYING A GAME'), findsOneWidget);
      expect(find.text('Limgrave'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('labels the card for the activity type it shows', (
      tester,
    ) async {
      const labels = {
        ActivityType.playing: 'PLAYING A GAME',
        ActivityType.streaming: 'LIVE ON STREAM',
        ActivityType.listening: 'LISTENING TO',
        ActivityType.watching: 'WATCHING',
        ActivityType.competing: 'COMPETING IN',
        ActivityType.unrecognised: 'ACTIVITY',
      };
      for (final entry in labels.entries) {
        await tester.pumpWidget(
          _host(
            Center(
              child: MemberProfilePopover(
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
                canMessage: true,
                onMessage: () {},
                now: _now,
              ),
            ),
          ),
        );

        expect(find.text(entry.value), findsOneWidget);
        // The custom status becomes the sentence under the name.
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

      expect(
        find.byKey(const ValueKey('member-profile-popover')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
