import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/domain/message_embed.dart';
import 'package:flucord/src/domain/reaction_repository.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/presentation/widgets/message_item.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('sends silently and resets the compact composer toggle', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    bool? sentSilently;

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageComposer(
              channelName: 'native',
              spaceName: 'Forge',
              customEmojis: const [],
              guildStickers: const [],
              isSending: false,
              onSend: (_, _, _, suppressNotifications) async {
                sentSilently = suppressNotifications;
                return true;
              },
              onCreatePoll: (_) async => false,
              onSendStickers: (_) async => false,
              onCancelReply: () {},
              onTyping: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('send-silently')));
    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'Quiet release',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await tester.pumpAndSettle();

    expect(sentSilently, isTrue);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('message-composer')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(find.byTooltip('Send silently'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suppresses and restores embeds from the message action bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const _MessageFlagHarness());

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('message-message-1'))),
    );
    await tester.pump();
    expect(find.text('Preview title'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('suppress-embeds-message-1')));
    await tester.pump();
    expect(find.text('Preview title'), findsNothing);
    expect(find.byTooltip('Show embeds'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('suppress-embeds-message-1')));
    await tester.pump();
    expect(find.text('Preview title'), findsOneWidget);
    expect(find.byTooltip('Suppress embeds'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MessageFlagHarness extends StatefulWidget {
  const _MessageFlagHarness();

  @override
  State<_MessageFlagHarness> createState() => _MessageFlagHarnessState();
}

class _MessageFlagHarnessState extends State<_MessageFlagHarness> {
  ChatMessage _message = ChatMessage(
    id: 'message-1',
    channelId: 'channel-1',
    authorId: 'bot-1',
    body: 'https://example.com/release',
    sentAt: DateTime.utc(2026, 7, 24, 8),
    embeds: [MessageEmbed(type: 'rich', title: 'Preview title')],
  );

  ChatWorkspace get _workspace => ChatWorkspace(
    spaces: const [_space],
    channels: const [_channel],
    members: const [_member],
    messages: [_message],
    currentMemberId: 'bot-1',
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 680,
          child: MessageItem(
            key: const ValueKey('message-message-1'),
            message: _message,
            member: _member,
            workspace: _workspace,
            grouped: false,
            isCurrentUser: true,
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
            onToggleSuppressEmbeds: (message) async {
              setState(() {
                final bit = DiscordMessageFlag.suppressEmbeds.bit;
                _message = message.copyWith(
                  flags: message.suppressesEmbeds
                      ? message.flags & ~bit
                      : message.flags | bit,
                );
              });
              return true;
            },
            linkLauncher: const _TestLinkLauncher(),
            onSelectChannel: (_) {},
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
  name: 'native',
  topic: '',
  kind: ChannelKind.text,
);

const _member = Member(
  id: 'bot-1',
  displayName: 'Fly',
  initials: 'FL',
  role: 'Bot',
  presence: Presence.online,
  colorValue: 0xff456b5a,
);

final class _TestLinkLauncher implements ExternalLinkLauncher {
  const _TestLinkLauncher();

  @override
  Future<bool> open(Uri uri) async => true;
}
