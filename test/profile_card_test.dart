import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/presentation/widgets/name_tags.dart';
import 'package:flucord/src/presentation/widgets/profile_card.dart';
import 'package:flucord/src/presentation/widgets/profile_card_data.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 4, 12);

const _freez = ProfileCardData(
  userId: '100000000000000002',
  displayName: 'Freez',
  monogram: 'F',
  username: 'freezz5126',
);

const _boots = CommunityRole(
  id: 'role-boots',
  spaceId: 'guild-1',
  name: 'Boots',
  position: 2,
  colorValue: 0xff46a758,
);

const _gamers = CommunityRole(
  id: 'role-gamers',
  spaceId: 'guild-1',
  name: 'Gamers',
  position: 1,
);

const _playAndDay = CommunitySpace(
  id: 'guild-2',
  name: 'Play&day',
  monogram: 'P&',
  colorValue: 0xff7a2e2e,
);

const _forge = CommunitySpace(
  id: 'guild-1',
  name: 'The Forge',
  monogram: 'TF',
  colorValue: 0xff2e4a7a,
);

Future<void> _pump(
  WidgetTester tester,
  ProfileCardData data, {
  ProfileCardActions actions = const ProfileCardActions(),
}) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Center(
          child: ProfileCard(data: data, actions: actions, now: _now),
        ),
      ),
    ),
  );
}

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _badgeShown(int index) => find.descendant(
  of: _key('profile-card-badges'),
  matching: find.byTooltip('Badge $index'),
);

/// [count] roles with names of different lengths, highest first.
List<CommunityRole> _manyRoles(int count) => [
  for (var index = 0; index < count; index++)
    CommunityRole(
      id: 'role-$index',
      spaceId: 'guild-1',
      name: 'Role ${'x' * (index % 7)}$index',
      position: count - index,
    ),
];

/// Where each role chip on screen sits.
List<Rect> _shownRoleRects(WidgetTester tester) => [
  for (final element in find
      .byWidgetPredicate(
        (widget) => switch (widget.key) {
          ValueKey(:final String value) =>
            value.startsWith('profile-card-role-') &&
                !value.startsWith('profile-card-role-choice-') &&
                !value.startsWith('profile-card-role-remove-'),
          _ => false,
        },
      )
      .evaluate())
    tester.getRect(find.byWidget(element.widget)),
];

ProfileCardData _with({
  String pronouns = '',
  ClanTag? clanTag,
  List<ProfileBadge> badges = const [],
  List<ProfileMutualFriend> mutualFriends = const [],
  List<ProfileMutualServer> mutualServers = const [],
  String bio = '',
  UserActivity? activity,
  List<CommunityRole>? roles,
  UserPresence? presence,
}) => ProfileCardData(
  userId: _freez.userId,
  displayName: _freez.displayName,
  monogram: _freez.monogram,
  username: _freez.username,
  pronouns: pronouns,
  clanTag: clanTag,
  badges: badges,
  mutualFriends: mutualFriends,
  mutualServers: mutualServers,
  bio: bio,
  activity: activity,
  roles: roles,
  presence: presence,
);

void main() {
  testWidgets('a bare card shows the name and username and nothing else', (
    tester,
  ) async {
    await _pump(tester, _freez);

    expect(find.text('Freez'), findsOneWidget);
    expect(find.text('freezz5126'), findsOneWidget);
    for (final part in [
      'profile-card-badges',
      'profile-card-mutual',
      'profile-card-bio',
      'activity-card',
      'profile-card-roles',
      'profile-card-message',
      'profile-card-add-friend',
      'profile-card-more',
      'profile-card-custom-status',
    ]) {
      expect(_key(part), findsNothing, reason: part);
    }
    expect(find.byType(ClanTagChip), findsNothing);
  });

  testWidgets('pronouns follow the username, and the clan tag sits after', (
    tester,
  ) async {
    await _pump(
      tester,
      _with(
        pronouns: 'he/him',
        clanTag: const ClanTag(tag: 'osu!', guildId: 'guild-9'),
      ),
    );

    expect(find.text('freezz5126 · he/him'), findsOneWidget);
    expect(
      tester.getRect(find.byType(ClanTagChip)).left,
      greaterThan(tester.getRect(_key('profile-card-handle')).right),
    );
  });

  testWidgets('the badges row shows three and counts the rest', (tester) async {
    await _pump(
      tester,
      _with(
        badges: [
          for (var index = 0; index < 5; index++)
            ProfileBadge(
              id: 'badge-$index',
              description: 'Badge $index',
              icon: '',
            ),
        ],
      ),
    );

    expect(_badgeShown(2), findsOneWidget);
    expect(_badgeShown(3), findsNothing);
    expect(find.text('+2'), findsOneWidget);

    await tester.tap(_key('profile-card-more-badges'));
    await tester.pumpAndSettle();
    expect(_badgeShown(3), findsOneWidget);
    expect(_badgeShown(4), findsOneWidget);
    expect(find.text('+2'), findsNothing);

    await tester.tap(_key('profile-card-more-badges'));
    await tester.pumpAndSettle();
    expect(_badgeShown(3), findsNothing);
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('many roles fold into two rows behind "+N", which unfolds', (
    tester,
  ) async {
    final roles = _manyRoles(40);
    await _pump(tester, _with(roles: roles));

    final folded = _shownRoleRects(tester);
    expect(folded.length, inInclusiveRange(2, roles.length - 1));
    final more = find.text('+${roles.length - folded.length}');
    expect(more, findsOneWidget);
    final rows = {
      for (final rect in [...folded, tester.getRect(more)])
        rect.center.dy.round(),
    };
    expect(rows, hasLength(2));

    await tester.tap(_key('profile-card-more-roles'));
    await tester.pumpAndSettle();
    expect(_shownRoleRects(tester), hasLength(roles.length));

    await tester.tap(_key('profile-card-more-roles'));
    await tester.pumpAndSettle();
    expect(_shownRoleRects(tester), hasLength(folded.length));
  });

  testWidgets('a few roles that fit show without "+N"', (tester) async {
    await _pump(tester, _with(roles: const [_boots, _gamers]));

    expect(_shownRoleRects(tester), hasLength(2));
    expect(_key('profile-card-more-roles'), findsNothing);
  });

  testWidgets('the mutual line counts friends and servers, and drops a zero', (
    tester,
  ) async {
    await _pump(
      tester,
      _with(
        mutualFriends: const [
          (friend: MutualFriend(id: 'a', displayName: 'A'), presence: null),
          (friend: MutualFriend(id: 'b', displayName: 'B'), presence: null),
        ],
        mutualServers: const [(space: _playAndDay, nickname: null)],
      ),
    );
    expect(find.text('2 mutual friends · 1 mutual server'), findsOneWidget);

    await _pump(
      tester,
      _with(
        mutualServers: const [
          (space: _playAndDay, nickname: null),
          (space: _forge, nickname: null),
        ],
      ),
    );
    expect(find.text('2 mutual servers'), findsOneWidget);
  });

  testWidgets(
    'the avatar, the name and "View full bio" open the full profile',
    (tester) async {
      final bio = List.filled(40, 'Carry player, lobby after nine.').join(' ');
      var opened = 0;
      await _pump(
        tester,
        _with(bio: bio),
        actions: ProfileCardActions(onOpenFullProfile: () => opened++),
      );

      await tester.tap(_key('profile-card-avatar'));
      await tester.tap(_key('profile-card-name'));
      // The bio is measured as laid out, so its link comes a frame later.
      await tester.pump();
      await tester.tap(_key('profile-card-view-bio'));

      expect(opened, 3);
    },
  );

  testWidgets('a bio that fits in the card has no "View full bio"', (
    tester,
  ) async {
    // Three lines at most, which is the card's limit. Measured, not counted:
    // the same number of characters in one long word would not fit.
    await _pump(
      tester,
      _with(bio: 'Carry player.\nLobby after nine.\nRust on weekends.'),
      actions: ProfileCardActions(onOpenFullProfile: () {}),
    );

    expect(_key('profile-card-bio'), findsOneWidget);
    expect(_key('profile-card-view-bio'), findsNothing);
  });

  testWidgets('a card with no full profile behind it opens nothing', (
    tester,
  ) async {
    final bio = List.filled(40, 'Carry player, lobby after nine.').join(' ');
    await _pump(tester, _with(bio: bio));

    expect(_key('profile-card-view-bio'), findsNothing);
    expect(_key('profile-card-name'), findsNothing);
    expect(_key('profile-card-avatar'), findsNothing);
  });

  testWidgets('a short bio has no "View full bio"', (tester) async {
    await _pump(tester, _with(bio: 'Carry player.'));

    expect(find.text('Carry player.'), findsOneWidget);
    expect(_key('profile-card-view-bio'), findsNothing);
  });

  testWidgets('the activity has its own card with its kind', (tester) async {
    await _pump(
      tester,
      _with(
        activity: const UserActivity(name: 'Dota 2', details: 'Ranked match'),
        presence: const UserPresence(
          status: Presence.online,
          activities: [
            UserActivity(
              name: 'Custom Status',
              type: ActivityType.customStatus,
              state: 'Looking for a party',
            ),
          ],
        ),
      ),
    );

    final card = _key('activity-card');
    expect(find.descendant(of: card, matching: find.text('Playing')), findsOne);
    expect(find.descendant(of: card, matching: find.text('Dota 2')), findsOne);
    expect(find.text('Ranked match'), findsOneWidget);
    expect(
      find.descendant(
        of: _key('profile-card-custom-status'),
        matching: find.text('Looking for a party'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('roles show as chips; "+" only for someone who can add them', (
    tester,
  ) async {
    await _pump(tester, _with(roles: const [_boots]));
    expect(_key('profile-card-role-role-boots'), findsOneWidget);
    expect(_key('profile-card-add-role'), findsNothing);

    CommunityRole? added;
    await _pump(
      tester,
      _with(roles: const [_boots]),
      actions: ProfileCardActions(
        addableRoles: const [_gamers],
        onAddRole: (role) => added = role,
      ),
    );
    await tester.tap(_key('profile-card-add-role'));
    await tester.pumpAndSettle();
    await tester.tap(_key('profile-card-role-choice-role-gamers'));
    await tester.pumpAndSettle();

    expect(added, _gamers);
  });

  testWidgets('outside a server there is no roles section', (tester) async {
    await _pump(
      tester,
      _with(),
      actions: ProfileCardActions(onAddRole: (_) {}),
    );

    expect(_key('profile-card-roles'), findsNothing);
  });

  testWidgets('add friend shows when the host offers it', (tester) async {
    var asked = false;
    await _pump(
      tester,
      _freez,
      actions: ProfileCardActions(onAddFriend: () => asked = true),
    );

    await tester.tap(_key('profile-card-add-friend'));

    expect(asked, isTrue);
  });

  testWidgets('the more menu runs the chosen row', (tester) async {
    var copied = false;
    await _pump(
      tester,
      _freez,
      actions: ProfileCardActions(
        menu: [
          ProfileCardMenuEntry(
            key: const ValueKey('copy-id'),
            label: 'Copy user ID',
            icon: FlucordIcons.id,
            onSelected: () => copied = true,
          ),
        ],
      ),
    );

    await tester.tap(_key('profile-card-more'));
    await tester.pumpAndSettle();
    await tester.tap(_key('copy-id'));
    await tester.pumpAndSettle();

    expect(copied, isTrue);
  });

  testWidgets('the message field hands over what was typed', (tester) async {
    String? sent;
    await _pump(
      tester,
      _freez,
      actions: ProfileCardActions(onMessage: (text) => sent = text),
    );

    expect(find.text('Message @Freez'), findsOneWidget);
    await tester.enterText(_key('profile-card-message'), '  gg  ');
    await tester.testTextInput.receiveAction(TextInputAction.send);

    expect(sent, 'gg');
  });
}
