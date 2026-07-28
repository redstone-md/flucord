import 'package:flucord/src/domain/moderation_report.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/domain/reaction_repository.dart';
import 'package:flucord/src/application/connection_controller.dart';
import 'package:flucord/src/domain/chat_repository.dart';
import 'package:flucord/src/domain/read_state.dart';
import 'package:flucord/src/presentation/widgets/channel_sidebar.dart';
import 'package:flucord/src/presentation/widgets/message_item.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what a report names', () {
    test('a message report names the channel and the message', () {
      const target = MessageReportTarget(
        channelId: 'channel-1',
        messageId: 'message-1',
      );

      expect(target.type, ReportType.message);
      expect(target.toEntityKeys(), {
        'channel_id': 'channel-1',
        'message_id': 'message-1',
      });
    });

    test('the first DM from a stranger is its own kind of report', () {
      const target = MessageReportTarget(
        channelId: 'channel-1',
        messageId: 'message-1',
        isFirstDirectMessage: true,
      );

      // Discord serves a different menu for it, so the type has to differ
      // before the menu is asked for rather than after it comes back.
      expect(target.type, ReportType.firstDm);
    });

    test('a server report names only the server', () {
      const target = GuildReportTarget('guild-1');

      expect(target.type, ReportType.guild);
      expect(target.toEntityKeys(), {'guild_id': 'guild-1'});
    });

    test('a user report from a DM omits the guild rather than nulling it', () {
      expect(const UserReportTarget(userId: 'user-1').toEntityKeys(), {
        'user_id': 'user-1',
      });
      expect(
        const UserReportTarget(
          userId: 'user-1',
          guildId: 'guild-1',
        ).toEntityKeys(),
        {'user_id': 'user-1', 'guild_id': 'guild-1'},
      );
    });
  });

  group('where a report is raised from', () {
    testWidgets('a message offers a report control', (tester) async {
      final reported = <String>[];
      await _pumpMessage(tester, onReport: (m) => reported.add(m.id));

      await tester.tap(find.byKey(const ValueKey('report-message-message-1')));
      await tester.pumpAndSettle();

      expect(reported, ['message-1']);
    });

    testWidgets('reporting oneself is not offered', (tester) async {
      // Discord withholds it there for the same reason: a report about your
      // own message is a report about yourself.
      await _pumpMessage(tester, onReport: (_) {}, isCurrentUser: true);

      expect(
        find.byKey(const ValueKey('report-message-message-1')),
        findsNothing,
      );
    });

    testWidgets('a transport with no report flow offers nothing', (
      tester,
    ) async {
      await _pumpMessage(tester);

      expect(
        find.byKey(const ValueKey('report-message-message-1')),
        findsNothing,
      );
    });

    testWidgets('a server offers a report control beside its settings', (
      tester,
    ) async {
      var reports = 0;
      await _pumpSidebar(tester, onReportServer: () => reports++);

      await tester.tap(find.byKey(const ValueKey('report-server')));
      await tester.pumpAndSettle();

      expect(reports, 1);
    });

    testWidgets('direct messages are no server to report', (tester) async {
      await _pumpSidebar(tester, direct: true, onReportServer: () {});

      expect(find.byKey(const ValueKey('report-server')), findsNothing);
    });
  });
}

Future<void> _pumpSidebar(
  WidgetTester tester, {
  VoidCallback? onReportServer,
  bool direct = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final workspace = direct ? _directWorkspace : _workspace;
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: ChannelSidebar(
          space: workspace.spaces.single,
          channels: workspace.channels,
          selectedChannelId: workspace.channels.single.id,
          onSelectChannel: (_) {},
          sessionMode: SessionMode.demo,
          connectionStatus: RepositoryConnectionStatus.connected,
          workspace: workspace,
          collapsedCategoryIds: const {},
          onToggleCategory: (_) {},
          onNewDirectMessage: () {},
          onReportServer: onReportServer,
          readState: ReadStateSnapshot.empty,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _directWorkspace = ChatWorkspace(
  spaces: const [CommunitySpace.directMessages()],
  channels: const [
    ConversationChannel(
      id: 'dm-1',
      spaceId: CommunitySpace.directMessagesId,
      name: 'Mira Chen',
      topic: '',
      kind: ChannelKind.text,
      recipientId: 'member-1',
    ),
  ],
  members: const [_member, _currentMember],
  messages: const [],
  currentMemberId: 'current-user',
);

Future<void> _pumpMessage(
  WidgetTester tester, {
  void Function(ChatMessage)? onReport,
  bool isCurrentUser = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 820,
            child: MessageItem(
              key: const ValueKey('reportable'),
              message: _message,
              member: _member,
              workspace: _workspace,
              grouped: false,
              isCurrentUser: isCurrentUser,
              onReply: (_) {},
              onEdit: (_, _) async => true,
              onDelete: (_) async {},
              onToggleReaction: (_, _) async {},
              onLoadReactionUsers: (_, _, _, _) async =>
                  const ReactionUsersPage(users: [], hasMore: false),
              onAddReaction: (_, _) async {},
              onCreateThread: (_, _, _) async => true,
              onTogglePin: (_) async {},
              onEndPoll: (_) async => true,
              onForward: (_, _) async => true,
              onToggleSuppressEmbeds: (_) async => true,
              onReport: onReport,
              linkLauncher: const _TestLinkLauncher(),
              onSelectChannel: (_) {},
            ),
          ),
        ),
      ),
    ),
  );

  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(
    tester.getCenter(find.byKey(const ValueKey('reportable'))),
  );
  await tester.pumpAndSettle();
}

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'space-1',
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'channel-1',
      spaceId: 'space-1',
      name: 'general',
      topic: 'General',
      kind: ChannelKind.text,
    ),
  ],
  members: const [_member, _currentMember],
  messages: [_message],
  currentMemberId: 'current-user',
);

const _currentMember = Member(
  id: 'current-user',
  displayName: 'You',
  initials: 'YO',
  role: 'Member',
  presence: Presence.online,
  colorValue: 0xff456b5a,
);

const _member = Member(
  id: 'member-1',
  displayName: 'Mira Chen',
  initials: 'MC',
  role: 'Design',
  presence: Presence.online,
  colorValue: 0xff665f82,
);

final _message = ChatMessage(
  id: 'message-1',
  channelId: 'channel-1',
  authorId: 'member-1',
  body: 'Buy followers here',
  sentAt: DateTime(2026, 7, 28, 10),
);

final class _TestLinkLauncher implements ExternalLinkLauncher {
  const _TestLinkLauncher();

  @override
  Future<bool> open(Uri uri) async => true;
}
