import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/domain/guild_management.dart';
import 'package:flucord/src/domain/reaction_repository.dart';
import 'package:flucord/src/presentation/widgets/guild_access_scope.dart';
import 'package:flucord/src/presentation/widgets/message_item.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a valid invite shows the server under the message text', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _row(
        previewInvite: (code) async => InvitePreview(
          code: code,
          name: 'Aurora',
          guildId: 'aurora-guild',
          approximateMemberCount: 1204,
          approximatePresenceCount: 312,
        ),
        onOpenInvite: (_, code) => opened.add(code),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("You've been invited to join a server"), findsOneWidget);
    expect(find.text('Aurora'), findsOneWidget);
    expect(find.text('312 Online'), findsOneWidget);
    expect(find.text('1204 Members'), findsOneWidget);

    final text = tester.getRect(_messageText);
    final card = tester.getRect(find.byKey(const ValueKey('invite-card')));
    expect(card.top, greaterThanOrEqualTo(text.bottom));
    expect(card.left, text.left, reason: 'the card sits in the text column');

    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    expect(opened, ['aurora'], reason: 'Join opens the existing join flow');
  });
}

final _messageText = find.textContaining('come hang out', findRichText: true);

/// One message row that links an invite, with the access surface above it.
Widget _row({
  required Future<InvitePreview> Function(String code) previewInvite,
  void Function(BuildContext context, String code)? onOpenInvite,
  String authorId = 'jack',
}) {
  final message = ChatMessage(
    id: 'message-1',
    channelId: 'channel-1',
    authorId: authorId,
    body: 'come hang out https://discord.gg/aurora',
    sentAt: DateTime.utc(2026, 11, 3, 8),
  );
  return MaterialApp(
    theme: FlucordTheme.dark,
    home: GuildAccessScope(
      onOpenInvite: onOpenInvite ?? (_, _) {},
      onOpenMessageLink: null,
      previewInvite: previewInvite,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 680,
            child: MessageItem(
              message: message,
              member: _member,
              workspace: ChatWorkspace(
                spaces: const [_space],
                channels: const [_channel],
                members: const [_member],
                messages: [message],
                currentMemberId: 'jack',
              ),
              grouped: false,
              isCurrentUser: authorId == 'jack',
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
              linkLauncher: const _NoLauncher(),
              onSelectChannel: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

const _space = CommunitySpace(
  id: 'guild-1',
  name: 'Forge',
  monogram: 'FO',
  colorValue: 0xff456b5a,
);

const _channel = ConversationChannel(
  id: 'channel-1',
  spaceId: 'guild-1',
  name: 'general',
  topic: '',
  kind: ChannelKind.text,
);

const _member = Member(
  id: 'jack',
  displayName: 'Jack',
  initials: 'JA',
  role: 'Member',
  presence: Presence.online,
  colorValue: 0xff456b5a,
);

final class _NoLauncher implements ExternalLinkLauncher {
  const _NoLauncher();

  @override
  Future<bool> open(Uri uri) async => false;
}
