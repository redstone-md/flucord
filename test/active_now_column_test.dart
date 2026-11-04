import 'package:flucord/src/application/active_friends.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/active_now_column.dart';
import 'package:flucord/src/presentation/widgets/activity_views.dart';
import 'package:flucord/src/presentation/widgets/member_avatar.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/flucord_icon_finder.dart';

// The Friends page's "Active now" column (FLUCORD-89): one card per friend
// who is playing, listening, watching or sitting in voice.

final _now = DateTime.utc(2026, 11, 4, 12);

int _startedAgo(Duration span) => _now.subtract(span).millisecondsSinceEpoch;

Member _person(
  String id,
  String name, {
  List<UserActivity> activities = const [],
}) => Member(
  id: id,
  displayName: name,
  initials: name.substring(0, 1),
  role: '',
  presence: Presence.online,
  colorValue: 0xff665f82,
  presenceDetail: UserPresence(status: Presence.online, activities: activities),
);

const _guild = CommunitySpace(
  id: 'guild-1',
  name: 'Play&day',
  monogram: 'P&',
  colorValue: 0xff8a3a3a,
);

const _voice = ConversationChannel(
  id: 'voice-1',
  spaceId: 'guild-1',
  name: 'Lounge',
  topic: '',
  kind: ChannelKind.voice,
);

Finder _card(String id) => find.byKey(ValueKey('active-friend-$id'));

Finder _inCard(String id, Finder matching) =>
    find.descendant(of: _card(id), matching: matching);

Future<void> _pump(
  WidgetTester tester,
  List<ActiveFriend> friends, {
  ValueChanged<ConversationChannel>? onOpenRoom,
}) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Row(
        children: [
          const Spacer(),
          ActiveNowColumn(
            friends: friends,
            onOpenRoom: onOpenRoom ?? (_) {},
            now: _now,
          ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('a game with details shows the match under the activity line', (
    tester,
  ) async {
    final freez = _person(
      'freez',
      'Freez',
      activities: [
        UserActivity(
          name: 'Dota 2',
          details: 'Ranked match',
          state: 'Dire',
          timestamps: ActivityTimestamps(
            startMs: _startedAgo(const Duration(hours: 1, minutes: 20)),
          ),
        ),
      ],
    );
    await _pump(tester, [ActiveFriend(person: freez)]);

    expect(find.text('Active now'), findsOneWidget);
    expect(_inCard('freez', find.text('Freez')), findsOneWidget);
    final line = _inCard('freez', find.byType(ActivitySummaryLine));
    expect(
      find.descendant(of: line, matching: find.text('Dota 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: line, matching: findFlucordIcon(FlucordIcons.game)),
      findsOneWidget,
    );
    expect(
      tester.getSize(_inCard('freez', find.byType(MemberAvatar))),
      const Size.square(32),
    );
    // The second block: art, the details, then the state with the time.
    expect(_inCard('freez', find.text('Ranked match')), findsOneWidget);
    expect(_inCard('freez', find.text('Dire · 1 h 20 min')), findsOneWidget);
    // No art from Discord, so the game's initials stand in.
    expect(_inCard('freez', find.text('D2')), findsOneWidget);
    expect(
      tester.getRect(find.text('Ranked match')).top,
      greaterThan(tester.getRect(line).bottom),
    );
  });

  testWidgets('a game without details is one line with the time on it', (
    tester,
  ) async {
    final acapulco = _person(
      'acapulco',
      'Acapulco',
      activities: [
        UserActivity(
          name: 'Tabletop Simulator',
          timestamps: ActivityTimestamps(
            startMs: _startedAgo(const Duration(minutes: 35)),
          ),
        ),
      ],
    );
    await _pump(tester, [ActiveFriend(person: acapulco)]);

    final line = _inCard('acapulco', find.byType(ActivitySummaryLine));
    expect(
      find.descendant(of: line, matching: find.text('Tabletop Simulator')),
      findsOneWidget,
    );
    expect(_inCard('acapulco', find.text(' · 35 min')), findsOneWidget);
    expect(_inCard('acapulco', find.text('TS')), findsNothing);
    expect(tester.getSize(_card('acapulco')).height, lessThan(80));
  });

  testWidgets('a rich presence with a state and no details keeps its block', (
    tester,
  ) async {
    final mira = _person(
      'mira',
      'Mira',
      activities: [
        UserActivity(
          name: 'Deep Rock Galactic',
          state: 'In a lobby',
          timestamps: ActivityTimestamps(
            startMs: _startedAgo(const Duration(minutes: 35)),
          ),
        ),
      ],
    );
    await _pump(tester, [ActiveFriend(person: mira)]);

    expect(_inCard('mira', find.text('In a lobby')), findsOneWidget);
    expect(_inCard('mira', find.text('35 min')), findsOneWidget);
    // The game's art block, here its initials.
    expect(_inCard('mira', find.text('DR')), findsOneWidget);
  });

  testWidgets('a friend in voice names the room and opens it when clicked', (
    tester,
  ) async {
    final wzrd = _person('wzrd', 'wzrd.');
    final room = ActiveFriendRoom(
      channel: _voice,
      space: _guild,
      people: [
        wzrd,
        _person('s', 'Sam'),
        _person('t', 'Tom'),
        _person('u', 'Uma'),
      ],
    );
    final opened = <ConversationChannel>[];
    await _pump(tester, [
      ActiveFriend(person: wzrd, room: room),
    ], onOpenRoom: opened.add);

    final line = _inCard('wzrd', find.byType(ActivitySummaryLine));
    expect(
      find.descendant(of: line, matching: find.text('In voice')),
      findsOneWidget,
    );
    expect(_inCard('wzrd', find.text('Lounge')), findsOneWidget);
    expect(_inCard('wzrd', find.text('Play&day · 4 people')), findsOneWidget);
    expect(_inCard('wzrd', find.text('P&')), findsOneWidget);
    // The friend's own avatar, then up to three faces from the room.
    expect(_inCard('wzrd', find.byType(MemberAvatar)), findsNWidgets(4));

    await tester.tap(_card('wzrd'));
    expect(opened, [_voice]);
  });

  testWidgets('with nobody active the column says so in one line', (
    tester,
  ) async {
    await _pump(tester, const []);

    expect(find.text('Active now'), findsOneWidget);
    expect(find.text("It's quiet for now"), findsOneWidget);
  });

  testWidgets('the column is 340 wide', (tester) async {
    await _pump(tester, const []);

    expect(tester.getSize(find.byType(ActiveNowColumn)).width, 340);
  });
}
