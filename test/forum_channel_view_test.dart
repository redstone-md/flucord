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

  testWidgets('picked tags ask for and show posts with any of them', (
    tester,
  ) async {
    final asked = <Set<String>>[];
    await _pumpForum(
      tester,
      posts: [
        _post('crash-on-start', ['tag-bug']),
        _post('dark-mode', ['tag-idea']),
        _post('chit-chat', []),
      ],
      onFilterTags: asked.add,
    );

    await tester.tap(find.byKey(const ValueKey('forum-filter-tag-bug')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('forum-filter-tag-idea')));
    await tester.pump();

    expect(asked, [
      {'tag-bug'},
      {'tag-bug', 'tag-idea'},
    ]);
    expect(find.text('crash-on-start'), findsOneWidget);
    expect(find.text('dark-mode'), findsOneWidget);
    expect(find.text('chit-chat'), findsNothing);
  });

  testWidgets('sorts the posts it is given into active and archived', (
    tester,
  ) async {
    await _pumpForum(
      tester,
      posts: const [
        ConversationChannel(
          id: 'post-open',
          spaceId: 'guild-1',
          name: 'still talking',
          topic: '',
          kind: ChannelKind.text,
          parentId: 'forum-1',
          isThread: true,
        ),
        ConversationChannel(
          id: 'post-closed',
          spaceId: 'guild-1',
          name: 'long done',
          topic: '',
          kind: ChannelKind.text,
          parentId: 'forum-1',
          isThread: true,
          isArchived: true,
        ),
      ],
    );

    expect(find.text('ACTIVE POSTS'), findsOneWidget);
    expect(find.text('ARCHIVED POSTS'), findsOneWidget);
    expect(find.text('still talking'), findsOneWidget);
    expect(find.text('long done'), findsOneWidget);
  });
}

Future<void> _pumpForum(
  WidgetTester tester, {
  bool isLoading = false,
  Object? error,
  VoidCallback? onRefresh,
  List<ConversationChannel> posts = const [],
  ValueChanged<Set<String>>? onFilterTags,
}) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: ForumChannelView(
        workspace: _workspace,
        channel: _forum,
        posts: posts,
        isLoading: isLoading,
        error: error,
        canLoadMore: false,
        onRefresh: onRefresh ?? () {},
        onLoadMore: () {},
        onFilterTags: onFilterTags ?? (_) {},
        onOpenPost: (_) {},
        onLoadPostPreview: (_) {},
        onCreatePost: (_, _, _, _, _) async => false,
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
  availableTags: [
    ForumTag(id: 'tag-bug', name: 'Bug', moderated: false),
    ForumTag(id: 'tag-idea', name: 'Idea', moderated: false),
  ],
);

ConversationChannel _post(String id, List<String> tagIds) =>
    ConversationChannel(
      id: id,
      spaceId: 'guild-1',
      name: id,
      topic: '',
      kind: ChannelKind.text,
      parentId: 'forum-1',
      isThread: true,
      appliedTagIds: tagIds,
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
