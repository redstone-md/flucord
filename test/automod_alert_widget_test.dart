import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flucord/src/domain/automod_rule.dart';
import 'package:flucord/src/domain/channel_capabilities.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/reaction_repository.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/presentation/widgets/message_item.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<AutoModAlertAction>> _hoverAlert(
  WidgetTester tester, {
  required ChatMessage message,
  ChannelCapabilities capabilities = ChannelCapabilities.none,
  bool wired = true,
}) async {
  final taken = <AutoModAlertAction>[];
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
              key: const ValueKey('alert-message'),
              message: message,
              member: _member,
              workspace: _workspace,
              grouped: false,
              isCurrentUser: false,
              capabilities: capabilities,
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
              onResolveAlert: wired
                  ? (_, action) async => taken.add(action)
                  : null,
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
    tester.getCenter(find.byKey(const ValueKey('alert-message'))),
  );
  await tester.pumpAndSettle();
  return taken;
}

void main() {
  testWidgets('an alert offers the four things a moderator can do', (
    tester,
  ) async {
    final taken = await _hoverAlert(
      tester,
      message: _alert,
      capabilities: ChannelCapabilities.unrestricted,
    );

    await tester.tap(
      find.byKey(const ValueKey('automod-alert-complete-alert-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('automod-alert-reopen-alert-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('automod-alert-delete-alert-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('automod-alert-feedback-alert-1')),
    );
    await tester.pumpAndSettle();

    expect(taken, [
      AutoModAlertAction.setCompleted,
      AutoModAlertAction.unsetCompleted,
      AutoModAlertAction.deleteUserMessage,
      AutoModAlertAction.submitFeedback,
    ]);
  });

  testWidgets('an ordinary message is not an alert', (tester) async {
    await _hoverAlert(
      tester,
      message: _ordinary,
      capabilities: ChannelCapabilities.unrestricted,
    );

    expect(
      find.byKey(const ValueKey('automod-alert-complete-message-1')),
      findsNothing,
    );
  });

  testWidgets('without Manage Messages the controls are withheld', (
    tester,
  ) async {
    // Discord checks the same permission before offering these, and an
    // affordance that always appears and then fails reads as a broken client.
    await _hoverAlert(tester, message: _alert, capabilities: _readOnly);

    expect(
      find.byKey(const ValueKey('automod-alert-complete-alert-1')),
      findsNothing,
    );
  });

  testWidgets('a transport that cannot resolve offers nothing', (tester) async {
    await _hoverAlert(
      tester,
      message: _alert,
      capabilities: ChannelCapabilities.unrestricted,
      wired: false,
    );

    expect(
      find.byKey(const ValueKey('automod-alert-complete-alert-1')),
      findsNothing,
    );
  });
}

/// Everything but the moderator's permission, so the withheld case is about
/// Manage Messages rather than about a channel nobody can act in.
const _readOnly = ChannelCapabilities(
  viewChannel: true,
  sendMessages: true,
  manageMessages: false,
  pinMessages: true,
  createPublicThreads: true,
  addReactions: true,
  attachFiles: true,
  embedLinks: true,
  moderateStage: false,
);

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
      name: 'automod-alerts',
      topic: 'Alerts',
      kind: ChannelKind.text,
    ),
  ],
  members: const [_member],
  messages: [_alert],
  currentMemberId: 'current-user',
);

const _member = Member(
  id: 'member-1',
  displayName: 'AutoMod',
  initials: 'AM',
  role: 'System',
  presence: Presence.online,
  colorValue: 0xff665f82,
);

final _alert = ChatMessage(
  id: 'alert-1',
  channelId: 'channel-1',
  authorId: 'member-1',
  body: 'Blocked a message in #general',
  sentAt: DateTime(2026, 7, 28, 9),
  type: DiscordMessageType.autoModerationAction,
);

final _ordinary = ChatMessage(
  id: 'message-1',
  channelId: 'channel-1',
  authorId: 'member-1',
  body: 'Morning',
  sentAt: DateTime(2026, 7, 28, 9, 1),
);

final class _TestLinkLauncher implements ExternalLinkLauncher {
  const _TestLinkLauncher();

  @override
  Future<bool> open(Uri uri) async => true;
}
