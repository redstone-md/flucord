import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
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
}

Widget _host(
  List<ChatMessage> messages, {
  bool isLoadingOlder = false,
  Object? olderLoadError,
  VoidCallback? onLoadOlder,
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
            channels: const [_channel],
            members: const [_member],
            messages: messages,
            currentMemberId: 'bot-1',
          ),
          channel: _channel,
          query: '',
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
