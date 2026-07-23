import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/presentation/widgets/message_list.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('shows load, progress, and retry history boundaries', (
    tester,
  ) async {
    final messages = List.generate(4, (index) => _message(index + 10));
    var requests = 0;

    await tester.pumpWidget(_host(messages, onLoadOlder: () => requests++));
    await tester.pump();
    expect(find.byKey(const ValueKey('load-older-messages')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('load-older-messages')));
    expect(requests, 1);

    await tester.pumpWidget(
      _host(messages, isLoadingOlder: true, onLoadOlder: () => requests++),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      _host(
        messages,
        olderLoadError: StateError('offline'),
        onLoadOlder: () => requests++,
      ),
    );
    expect(find.text('Older messages unavailable'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('retry-older-messages')));
    expect(requests, 2);
  });

  testWidgets('preserves the visible message when history is prepended', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final current = List.generate(30, (index) => _message(index + 10));

    await tester.pumpWidget(_host(current));
    await tester.pump();
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    final anchor = find.byKey(const ValueKey('message-m020'));
    expect(anchor, findsOneWidget);
    final before = tester.getTopLeft(anchor).dy;

    await tester.pumpWidget(
      _host([...List.generate(10, _message), ...current]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-m020')), findsOneWidget);
    final after = tester.getTopLeft(anchor).dy;
    expect(after, closeTo(before, 1));
  });

  testWidgets('positions the timeline at the first unread message', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final messages = List.generate(50, _message);
    final channel = _channel.copyWith(firstUnreadMessageId: 'm025');

    await tester.pumpWidget(_host(messages, channel: channel));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('unread-message-boundary')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('New messages'), findsOneWidget);
    final unreadMessage = find.byKey(const ValueKey('message-m025'));
    expect(unreadMessage, findsOneWidget);
    expect(tester.getTopLeft(unreadMessage).dy, inInclusiveRange(60, 250));
    expect(find.byKey(const ValueKey('jump-to-unread')), findsNothing);
    semantics.dispose();
  });

  testWidgets('hides the unread boundary while filtering messages', (
    tester,
  ) async {
    final channel = _channel.copyWith(firstUnreadMessageId: 'm010');
    await tester.pumpWidget(
      _host(List.generate(20, _message), channel: channel, query: 'Message 15'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('unread-message-boundary')), findsNothing);
    expect(find.textContaining('Message 15'), findsOneWidget);
  });
}

Widget _host(
  List<ChatMessage> messages, {
  bool isLoadingOlder = false,
  Object? olderLoadError,
  VoidCallback? onLoadOlder,
  ConversationChannel channel = _channel,
  String query = '',
}) {
  return MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: SizedBox(
        width: 700,
        height: 500,
        child: MessageList(
          workspace: ChatWorkspace(
            spaces: const [_space],
            channels: [channel],
            members: const [_member],
            messages: messages,
            currentMemberId: 'bot-1',
          ),
          channel: channel,
          query: query,
          onReply: (_) {},
          onEdit: (_, _) async => true,
          onDelete: (_) async {},
          onToggleReaction: (_, _) async {},
          onAddReaction: (_, _) async {},
          onTogglePin: (_) async {},
          canLoadOlder: true,
          isLoadingOlder: isLoadingOlder,
          olderLoadError: olderLoadError,
          onLoadOlder: onLoadOlder ?? () {},
          externalLinkLauncher: const _TestLinkLauncher(),
          onSelectChannel: (_) {},
        ),
      ),
    ),
  );
}

ChatMessage _message(int index) => ChatMessage(
  id: 'm${index.toString().padLeft(3, '0')}',
  channelId: 'channel-1',
  authorId: 'bot-1',
  body: 'Message $index with enough content to keep row height stable.',
  sentAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: index)),
);

const _space = CommunitySpace(
  id: 'space-1',
  name: 'Forge',
  monogram: 'FO',
  colorValue: 0xff456b5a,
);

const _channel = ConversationChannel(
  id: 'channel-1',
  spaceId: 'space-1',
  name: 'general',
  topic: 'History',
  kind: ChannelKind.text,
);

const _member = Member(
  id: 'bot-1',
  displayName: 'Flucord',
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
