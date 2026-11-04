import 'package:flucord/src/application/active_friends.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/presentation/widgets/profile_card.dart';
import 'package:flucord/src/presentation/widgets/profile_card_data.dart';
import 'package:flucord/src/theme/flucord_radius.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// FLUCORD-91: the full profile window. The card on the left, tabs on the
// right, and every part hidden when there is nothing to put in it.

final _now = DateTime.utc(2026, 11, 4, 12);

const _playAndDay = CommunitySpace(
  id: '200000000000000002',
  name: 'Play&day',
  monogram: 'P&',
  colorValue: 0xff7a2e2e,
);

const _lounge = ConversationChannel(
  id: '300000000000000050',
  spaceId: '200000000000000002',
  name: 'Lounge',
  topic: '',
  kind: ChannelKind.voice,
);

const _wzrd = MutualFriend(id: '100000000000000009', displayName: 'wzrd.');

const _bare = ProfileCardData(
  userId: '100000000000000002',
  displayName: 'Freez',
  monogram: 'F',
  username: 'freezz5126',
);

ProfileCardData _full({
  List<ProfileMutualFriend> friends = const [],
  List<ProfileMutualServer> servers = const [],
  UserActivity? activity,
  ActiveFriendRoom? voiceRoom,
  String bio = '',
}) => ProfileCardData(
  userId: _bare.userId,
  displayName: _bare.displayName,
  monogram: _bare.monogram,
  username: _bare.username,
  bio: bio,
  mutualFriends: friends,
  mutualServers: servers,
  activity: activity,
  voiceRoom: voiceRoom,
  memberSince: DateTime.utc(2019, 6, 12),
  serverSince: (serverName: 'Play&day', since: DateTime.utc(2026, 1, 29)),
  friendsSince: DateTime.utc(2025, 4, 21),
  connections: const [
    ProfileConnection(type: 'github', name: 'freezz5126'),
    ProfileConnection(type: 'battlenet', name: 'freez#2112'),
  ],
);

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _pump(
  WidgetTester tester,
  ProfileCardData data, {
  ProfileCardActions actions = const ProfileCardActions(),
  Widget? note,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showFullProfile(
                context: context,
                builder: (_) => FullProfile(
                  data: data,
                  actions: actions,
                  note: note,
                  now: _now,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens over the app at the window radius and closes with Escape '
      'or a click outside', (tester) async {
    await _pump(tester, _bare);

    final window = tester.widget<Dialog>(find.byType(Dialog));
    expect(
      (window.shape! as RoundedRectangleBorder).borderRadius,
      FlucordRadius.window,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_key('full-profile'), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(_key('full-profile'), findsNothing);
  });

  testWidgets('the card sits 8 in from the top and left and runs to the '
      'bottom edge', (tester) async {
    await _pump(tester, _bare);

    final window = tester.getRect(_key('full-profile'));
    final card = tester.getRect(_key('full-profile-card'));
    expect(card.left - window.left, 8);
    expect(card.top - window.top, 8);
    expect(card.bottom, window.bottom);
  });

  testWidgets('a tab with nobody in it is hidden', (tester) async {
    await _pump(tester, _bare);

    expect(_key('full-profile-tab-activity'), findsOneWidget);
    expect(_key('full-profile-tab-friends'), findsNothing);
    expect(_key('full-profile-tab-servers'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _pump(
      tester,
      _full(
        friends: const [(friend: _wzrd, presence: null)],
        servers: const [
          (space: _playAndDay, nickname: 'Freez'),
          (
            space: CommunitySpace(
              id: '200000000000000003',
              name: 'Murmur',
              monogram: 'M',
              colorValue: 0xff3e3a6e,
            ),
            nickname: null,
          ),
        ],
      ),
    );

    expect(find.text('1 Mutual friend'), findsOneWidget);
    expect(find.text('2 Mutual servers'), findsOneWidget);
  });

  testWidgets('with nothing going on, the activity tab says so in one line', (
    tester,
  ) async {
    await _pump(tester, _bare);

    expect(_key('activity-card'), findsNothing);
    expect(_key('voice-room-card'), findsNothing);
    expect(_key('full-profile-no-activity'), findsOneWidget);
  });

  testWidgets('the activity and the voice room show, and Join opens the room', (
    tester,
  ) async {
    String? joined;
    await _pump(
      tester,
      _full(
        activity: const UserActivity(name: 'Dota 2', details: 'Ranked match'),
        voiceRoom: const ActiveFriendRoom(
          channel: _lounge,
          space: _playAndDay,
          people: [],
        ),
      ),
      actions: ProfileCardActions(onJoinVoice: (id) => joined = id),
    );

    expect(_key('activity-card'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('voice-room-card'),
        matching: find.text('Lounge'),
      ),
      findsOneWidget,
    );
    expect(find.text('in Play&day · 0 people'), findsOneWidget);
    expect(_key('full-profile-no-activity'), findsNothing);

    await tester.tap(_key('voice-room-join'));
    expect(joined, _lounge.id);
  });

  testWidgets('a mutual friend opens their card and a server opens itself', (
    tester,
  ) async {
    String? friendId;
    String? serverId;
    await _pump(
      tester,
      _full(
        friends: const [
          (
            friend: _wzrd,
            presence: UserPresence(status: Presence.online),
          ),
        ],
        servers: const [(space: _playAndDay, nickname: 'Freezy')],
      ),
      actions: ProfileCardActions(
        onOpenProfile: (id, _) => friendId = id,
        onOpenServer: (id) => serverId = id,
      ),
    );

    await tester.tap(_key('full-profile-tab-friends'));
    await tester.pumpAndSettle();
    expect(find.text('Online'), findsOneWidget);
    await tester.tap(_key('full-profile-friend-${_wzrd.id}'));
    expect(friendId, _wzrd.id);

    await tester.tap(_key('full-profile-tab-servers'));
    await tester.pumpAndSettle();
    expect(find.text('Freezy'), findsOneWidget);
    await tester.tap(_key('full-profile-server-${_playAndDay.id}'));
    expect(serverId, _playAndDay.id);
  });

  testWidgets('the card lists the dates, the connections and the note', (
    tester,
  ) async {
    Uri? opened;
    await _pump(
      tester,
      _full(bio: 'Carry player.'),
      actions: ProfileCardActions(onOpenLink: (uri) => opened = uri),
      note: const Text('note-slot'),
    );

    expect(find.text('Carry player.'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('full-profile-member-since'),
        matching: find.text('Discord Jun 12, 2019 · Play&day Jan 29, 2026'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _key('full-profile-friends-since'),
        matching: find.text('Apr 21, 2025'),
      ),
      findsOneWidget,
    );
    expect(find.text('note-slot'), findsOneWidget);

    await tester.tap(_key('profile-connection-github'));
    expect(opened, Uri.parse('https://github.com/freezz5126'));
    // Battle.net has no public page, so its row opens nothing.
    await tester.tap(_key('profile-connection-battlenet'));
    expect(opened, Uri.parse('https://github.com/freezz5126'));
  });

  testWidgets('a bare profile hides what it has nothing for', (tester) async {
    await _pump(tester, _bare);

    for (final part in [
      'full-profile-member-since',
      'full-profile-friends-since',
      'full-profile-connections',
      'profile-card-roles',
      'full-profile-message',
      'full-profile-add-friend',
      'full-profile-more',
    ]) {
      expect(_key(part), findsNothing, reason: part);
    }
  });

  testWidgets('the window shows every role, unfolded', (tester) async {
    final roles = [
      for (var index = 0; index < 40; index++)
        CommunityRole(
          id: 'role-$index',
          spaceId: _playAndDay.id,
          name: 'Role number $index',
          position: 40 - index,
        ),
    ];
    await _pump(
      tester,
      ProfileCardData(
        userId: _bare.userId,
        displayName: _bare.displayName,
        monogram: _bare.monogram,
        roles: roles,
      ),
    );

    for (final role in roles) {
      expect(_key('profile-card-role-${role.id}'), findsOneWidget);
    }
    expect(_key('profile-card-more-roles'), findsNothing);
  });

  testWidgets('scrolling the card leaves the window in place', (tester) async {
    await _pump(
      tester,
      _full(bio: List.filled(80, 'Carry player, lobby after nine.').join(' ')),
      size: const Size(1280, 600),
    );
    final window = tester.getRect(_key('full-profile'));
    final tabs = tester.getRect(_key('full-profile-tab-activity'));
    final name = tester.getRect(find.text('Freez'));

    await tester.drag(_key('full-profile-card-scroll'), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tester.getRect(_key('full-profile')), window);
    expect(tester.getRect(_key('full-profile-tab-activity')), tabs);
    expect(tester.getRect(find.text('Freez')).top, lessThan(name.top));
  });
}
