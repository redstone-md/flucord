import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/forum_channel_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('shows the initial forum loading state', (tester) async {
    await _pumpForum(tester, isLoading: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No posts yet'), findsNothing);
  });

  testWidgets('shows the forum error and retry state', (tester) async {
    var retries = 0;
    await _pumpForum(
      tester,
      error: StateError('offline'),
      onRefresh: () => retries++,
    );

    expect(find.text('Posts unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('shows the empty forum state', (tester) async {
    await _pumpForum(tester);

    expect(find.text('No posts yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('create-forum-post')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpForum(
  WidgetTester tester, {
  bool isLoading = false,
  Object? error,
  VoidCallback? onRefresh,
}) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: ForumChannelView(
        workspace: _workspace,
        channel: _forum,
        archivedPosts: const [],
        isLoading: isLoading,
        error: error,
        canLoadMore: false,
        onRefresh: onRefresh ?? () {},
        onLoadMore: () {},
        onOpenPost: (_) {},
        onCreatePost: (_, _, _, _) async => false,
      ),
    ),
  ),
);

const _forum = ConversationChannel(
  id: 'forum-1',
  spaceId: 'guild-1',
  name: 'field-reports',
  topic: 'Post reports here.',
  kind: ChannelKind.forum,
);

final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'FO',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: const [_forum],
  members: const [],
  messages: const [],
  currentMemberId: 'bot-1',
);
