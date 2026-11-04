import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/presentation/widgets/leave_server_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the leave control on the server header asks first', (
    tester,
  ) async {
    var leaveRequested = 0;
    var confirmed = false;
    final workspace = _workspace();

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                Expanded(
                  child: ChannelSidebar(
                    space: workspace.spaces.single,
                    channels: workspace.channels,
                    selectedChannelId: 'forge-general',
                    onSelectChannel: (_) {},
                    sessionMode: SessionMode.demo,
                    connectionStatus: RepositoryConnectionStatus.connected,
                    categories: const [],
                    currentMember: workspace.memberById('jack'),
                    memberOf: workspace.memberOrNull,
                    channelOf: workspace.channelOrNull,
                    collapsedCategoryIds: const {},
                    onToggleCategory: (_) {},
                    onNewDirectMessage: () {},
                    readState: ReadStateSnapshot.empty,
                    onLeaveServer: () async {
                      leaveRequested++;
                      confirmed = await showLeaveServerConfirmation(
                        context,
                        space: workspace.spaces.single,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await _chooseFromServerMenu(tester, 'leave-server');

    // The confirmation names the server and what disappears with it.
    expect(find.byKey(const ValueKey('leave-server-dialog')), findsOneWidget);
    expect(find.text('Leave The Forge?'), findsOneWidget);
    expect(leaveRequested, 1);
    // A card under the words shows the server being left, by its tile and
    // its name.
    final card = find.byKey(const ValueKey('leave-server-card'));
    expect(
      find.descendant(of: card, matching: find.text('TF')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('The Forge')),
      findsOneWidget,
    );

    // Cancelling leaves the server where it is.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('leave-server-dialog')),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
    expect(find.byKey(const ValueKey('leave-server-dialog')), findsNothing);

    // Confirming answers yes, and the shell carries the leave from there.
    await _chooseFromServerMenu(tester, 'leave-server');
    await tester.tap(find.byKey(const ValueKey('leave-server-confirm')));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('the direct-messages space shows no leave control', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ChannelSidebar(
            space: const CommunitySpace.directMessages(),
            channels: const [],
            selectedChannelId: null,
            onSelectChannel: (_) {},
            sessionMode: SessionMode.demo,
            connectionStatus: RepositoryConnectionStatus.connected,
            categories: const [],
            currentMember: _workspace().memberById('jack'),
            memberOf: (_) => null,
            channelOf: (_) => null,
            collapsedCategoryIds: const {},
            onToggleCategory: (_) {},
            onNewDirectMessage: () {},
            readState: ReadStateSnapshot.empty,
            onLeaveServer: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('space-menu')), findsNothing);
  });

  testWidgets('the header gives the name room and one menu for its actions', (
    tester,
  ) async {
    final workspace = _workspace();
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: ChannelSidebar(
            space: workspace.spaces.single,
            channels: workspace.channels,
            selectedChannelId: 'forge-general',
            onSelectChannel: (_) {},
            sessionMode: SessionMode.demo,
            connectionStatus: RepositoryConnectionStatus.connected,
            categories: const [],
            currentMember: workspace.memberById('jack'),
            memberOf: workspace.memberOrNull,
            channelOf: workspace.channelOrNull,
            collapsedCategoryIds: const {},
            onToggleCategory: (_) {},
            onNewDirectMessage: () {},
            readState: ReadStateSnapshot.empty,
            onOpenServerSettings: () {},
            onLeaveServer: () {},
            onReportServer: () {},
            onNotificationRequest: (_, _) {},
          ),
        ),
      ),
    );

    // The sidebar is 236 wide: this is everything but its padding and the
    // menu's arrow.
    expect(tester.getSize(find.text('The Forge')).width, greaterThan(170));

    await tester.tap(find.byKey(const ValueKey('space-menu')));
    await tester.pumpAndSettle();
    for (final label in const [
      'Server settings',
      'Notification settings',
      'Report server',
      'Leave server',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });
}

Future<void> _chooseFromServerMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const ValueKey('space-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(item)));
  await tester.pumpAndSettle();
}

ChatWorkspace _workspace() => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'forge',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'forge-general',
      spaceId: 'forge',
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  members: const [
    Member(
      id: 'jack',
      displayName: 'Jack',
      initials: 'JA',
      role: 'member',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: {'forge'},
    ),
  ],
  messages: const [],
  currentMemberId: 'jack',
);
