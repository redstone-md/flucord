import 'dart:async';

import 'package:flucord/src/application/guild_member_list_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/guild_member_list.dart';
import 'package:flucord/src/domain/guild_member_list_repository.dart';
import 'package:flucord/src/presentation/widgets/member_roster_view.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GuildMemberList roster({
    required List<GuildMemberListRow?> rows,
    required List<GuildMemberListGroup> groups,
  }) => GuildMemberList(
    guildId: 'guild-1',
    listId: 'everyone',
    rows: rows,
    groups: groups,
    memberCount: 3,
    onlineCount: 2,
    version: 1,
  );

  final sample = roster(
    rows: const [
      GuildMemberListGroupRow(groupId: 'role-a', count: 2),
      GuildMemberListMemberRow('111111111111111111'),
      GuildMemberListMemberRow('222222222222222222'),
      GuildMemberListGroupRow(groupId: 'offline', count: 1),
      null,
    ],
    groups: const [
      GuildMemberListGroup(id: 'role-a', count: 2, index: 0),
      GuildMemberListGroup(id: 'offline', count: 1, index: 3),
    ],
  );

  Future<GuildMemberListController> pumpSidebar(
    WidgetTester tester, {
    required _FakeMemberListRepository repository,
    List<Member> members = const [_jack],
    String? channelId = 'channel-1',
    ValueChanged<Member>? onMessage,
  }) async {
    final controller = GuildMemberListController(
      () => repository,
      scrollDebounce: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: SizedBox()),
              MemberSidebar(
                members: members,
                spaceId: 'guild-1',
                channelId: channelId,
                memberList: controller,
                roles: const [
                  CommunityRole(
                    id: 'role-a',
                    spaceId: 'guild-1',
                    name: 'Architects',
                    position: 5,
                  ),
                  CommunityRole(
                    id: 'role-a',
                    spaceId: 'guild-2',
                    name: 'Wrong guild',
                    position: 5,
                  ),
                ],
                currentMemberId: _jack.id,
                onMessage: onMessage ?? (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('renders the roster the server laid out', (tester) async {
    final repository = _FakeMemberListRepository()..cached = sample;

    await pumpSidebar(tester, repository: repository);
    await tester.pump();

    expect(find.text('Architects - 2'), findsOneWidget);
    expect(find.text('Offline - 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('member-row-111111111111111111')),
      findsOneWidget,
    );
    // A member row whose member has not been cached yet, and a row inside a
    // range that has not arrived, both hold their place.
    expect(
      find.byKey(const ValueKey('member-row-placeholder-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('member-row-placeholder-4')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('subscribes the head page for the watched channel', (
    tester,
  ) async {
    final repository = _FakeMemberListRepository();

    await pumpSidebar(tester, repository: repository);

    expect(repository.subscribed.first.$2, 'channel-1');
    expect(repository.subscribed.first.$3, [
      [0, 99],
    ]);
  });

  testWidgets('renders a header row the groups table has not caught up to', (
    tester,
  ) async {
    final repository = _FakeMemberListRepository()
      ..cached = roster(
        rows: const [
          GuildMemberListGroupRow(groupId: 'online', count: 0),
          GuildMemberListGroupRow(groupId: 'role-missing', count: 4),
          GuildMemberListGroupRow(groupId: 'unknown', count: 1),
        ],
        groups: const [GuildMemberListGroup(id: 'online', count: 0, index: 0)],
      );

    await pumpSidebar(tester, repository: repository);
    await tester.pump();

    expect(find.text('Online - 0'), findsOneWidget);
    // An unresolvable role keeps its count and loses its name, as Discord does.
    expect(find.text(' - 4'), findsOneWidget);
    expect(find.text('Unknown - 1'), findsOneWidget);
  });

  testWidgets('opens the profile popover from a roster row', (tester) async {
    final repository = _FakeMemberListRepository()..cached = sample;
    Member? messaged;

    await pumpSidebar(
      tester,
      repository: repository,
      members: const [_jack, _mira],
      onMessage: (member) => messaged = member,
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('member-row-222222222222222222')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('member-profile-popover')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('message-member')));
    await tester.pump();
    expect(messaged?.id, '222222222222222222');
  });

  testWidgets('scrolling subscribes the pages it reaches', (tester) async {
    final repository = _FakeMemberListRepository()
      ..cached = roster(
        rows: List<GuildMemberListRow?>.filled(400, null),
        groups: const [
          GuildMemberListGroup(id: 'online', count: 399, index: 0),
        ],
      );

    await pumpSidebar(tester, repository: repository);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pump(const Duration(milliseconds: 50));

    // The head page stays subscribed no matter how far the panel scrolls.
    expect(repository.subscribed.last.$3, [
      [0, 99],
      [100, 199],
    ]);
  });

  testWidgets('falls back to the cached members before a roster lands', (
    tester,
  ) async {
    final repository = _FakeMemberListRepository();

    await pumpSidebar(
      tester,
      repository: repository,
      members: const [_jack, _mira],
    );
    await tester.pump();

    expect(find.text('Architect - 1'), findsOneWidget);
    expect(find.text('Offline - 1'), findsOneWidget);
    expect(find.byType(MemberRosterView), findsNothing);
  });

  testWidgets('releases the subscription when the panel closes', (
    tester,
  ) async {
    final repository = _FakeMemberListRepository();

    await pumpSidebar(tester, repository: repository);
    await tester.pumpWidget(
      MaterialApp(theme: FlucordTheme.dark, home: const Scaffold()),
    );

    expect(repository.unsubscribed, [('guild-1', 'channel-1')]);
  });

  testWidgets('follows the channel the panel is pointed at', (tester) async {
    final repository = _FakeMemberListRepository();

    await pumpSidebar(tester, repository: repository);
    await pumpSidebar(tester, repository: repository, channelId: 'channel-2');

    expect(repository.subscribed.last.$2, 'channel-2');
  });

  testWidgets('closes the profile when its member leaves the roster', (
    tester,
  ) async {
    final repository = _FakeMemberListRepository()..cached = sample;
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);
    var members = const [_jack, _mira];
    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Scaffold(
              body: Row(
                children: [
                  const Expanded(child: SizedBox()),
                  MemberSidebar(
                    members: members,
                    spaceId: 'guild-1',
                    channelId: 'channel-1',
                    memberList: controller,
                    currentMemberId: _jack.id,
                    onMessage: (_) {},
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('member-row-222222222222222222')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('member-profile-popover')),
      findsOneWidget,
    );

    updateHost(() => members = const [_jack]);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('member-profile-popover')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the roster in a compact window without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeMemberListRepository()..cached = sample;

    await pumpSidebar(
      tester,
      repository: repository,
      members: const [_jack, _longName],
    );
    await tester.pump();

    expect(find.byType(MemberRosterView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _FakeMemberListRepository implements GuildMemberListRepository {
  final StreamController<GuildMemberList> _updates =
      StreamController.broadcast();
  final List<(String, String, List<List<int>>)> subscribed = [];
  final List<(String, String)> unsubscribed = [];
  GuildMemberList? cached;

  @override
  Stream<GuildMemberList> get memberListUpdates => _updates.stream;

  @override
  String memberListIdFor({
    required String guildId,
    required String channelId,
  }) => 'everyone';

  @override
  GuildMemberList? memberListFor({
    required String guildId,
    required String listId,
  }) => cached;

  @override
  void subscribeMemberRanges({
    required String guildId,
    required String channelId,
    required List<List<int>> ranges,
  }) => subscribed.add((
    guildId,
    channelId,
    ranges.map(List<int>.from).toList(growable: false),
  ));

  @override
  void unsubscribeMemberRanges({
    required String guildId,
    required String channelId,
  }) => unsubscribed.add((guildId, channelId));

  /// What the surface asked to search for, so a test can check it asked.
  final List<(String, String)> searches = [];

  @override
  void searchGuildMembers({
    required String guildId,
    required String query,
    int limit = 25,
  }) => searches.add((guildId, query));
}

const _jack = Member(
  id: '111111111111111111',
  displayName: 'Jack',
  initials: 'JK',
  role: 'Architect',
  presence: Presence.online,
  colorValue: 0xff48745f,
  spaceIds: {'guild-1'},
  rolesBySpace: {'guild-1': 'Architect'},
);

const _mira = Member(
  id: '222222222222222222',
  displayName: 'Mira Chen',
  initials: 'MC',
  role: 'Product design',
  presence: Presence.offline,
  colorValue: 0xff665f82,
  spaceIds: {'guild-1'},
  rolesBySpace: {'guild-1': 'Product design'},
);

const _longName = Member(
  id: '222222222222222222',
  displayName: 'Mira Chen with an unreasonably long display name',
  initials: 'MC',
  role: 'Product design and platform architecture for everything',
  presence: Presence.online,
  colorValue: 0xff665f82,
  spaceIds: {'guild-1'},
  rolesBySpace: {'guild-1': 'Product design and platform architecture'},
);
