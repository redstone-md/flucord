import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/guild_member_list_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/guild_member_list.dart';
import 'package:flucord/src/domain/guild_member_list_repository.dart';
import 'package:flucord/src/presentation/widgets/member_sidebar.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('typing narrows the list to matching names', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeMemberListRepository();
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    expect(find.text('Mira Chen'), findsOneWidget);
    expect(find.text('Roman Vale'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('member-search')), 'Mira');
    await tester.pumpAndSettle();
    // The panel waits for typing to settle before it spends a socket ask.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Mira Chen'), findsOneWidget);
    expect(find.text('Roman Vale'), findsNothing);
    // The panel asked the guild about the same query, through the member
    // chunks the mention completion rides.
    expect(repository.searches, [('guild-1', 'Mira')]);
  });

  testWidgets('a blank query gives the roster back', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeMemberListRepository();
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(controller));
    await tester.enterText(find.byKey(const ValueKey('member-search')), 'Mira');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('member-search')), '');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Mira Chen'), findsOneWidget);
    expect(find.text('Roman Vale'), findsOneWidget);
    // Clearing asks nothing: an empty query is not a search.
    expect(repository.searches, hasLength(1));
  });

  testWidgets('a member found by the chunk route appears in the results', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeMemberListRepository();
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);

    late StateSetter updateHost;
    var members = [_mira, _roman];
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
                    currentMemberId: _me,
                    onMessage: (_) {},
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(const ValueKey('member-search')), 'Mira');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // The chunk route answered with somebody the local table never held, and
    // they arrived as an ordinary member update: the results list shows them.
    updateHost(() => members = [...members, _miraSecondAccount]);
    await tester.pumpAndSettle();

    expect(find.text('Mira Chen'), findsOneWidget);
    expect(find.text('Mira Second'), findsOneWidget);
    expect(find.text('Roman Vale'), findsNothing);
  });
}

Widget _host(GuildMemberListController controller) => MaterialApp(
  theme: FlucordTheme.dark,
  home: Scaffold(
    body: Row(
      children: [
        const Expanded(child: SizedBox()),
        MemberSidebar(
          members: const [_mira, _roman],
          spaceId: 'guild-1',
          currentMemberId: _me,
          onMessage: (_) {},
          memberList: controller,
        ),
      ],
    ),
  ),
);

const _me = '111111111111111111';
const _mira = Member(
  id: '222222222222222222',
  displayName: 'Mira Chen',
  initials: 'MC',
  role: 'Product design',
  presence: Presence.online,
  colorValue: 0xff665f82,
  spaceIds: {'guild-1'},
);
const _miraSecondAccount = Member(
  id: '555555555555555555',
  displayName: 'Mira Second',
  initials: 'MS',
  role: 'Product design',
  presence: Presence.online,
  colorValue: 0xff665f82,
  spaceIds: {'guild-1'},
);
const _roman = Member(
  id: '333333333333333333',
  displayName: 'Roman Vale',
  initials: 'RV',
  role: 'Infrastructure',
  presence: Presence.offline,
  colorValue: 0xff506674,
  spaceIds: {'guild-1'},
);

final class _FakeMemberListRepository implements GuildMemberListRepository {
  final StreamController<GuildMemberList> _updates =
      StreamController.broadcast();
  final List<(String, String)> searches = [];

  void publish(GuildMemberList list) => _updates.add(list);

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
  }) => null;

  @override
  void subscribeMemberRanges({
    required String guildId,
    required String channelId,
    required List<List<int>> ranges,
  }) {}

  @override
  void unsubscribeMemberRanges({
    required String guildId,
    required String channelId,
  }) {}

  @override
  void searchGuildMembers({
    required String guildId,
    required String query,
    int limit = 25,
  }) => searches.add((guildId, query));
}
