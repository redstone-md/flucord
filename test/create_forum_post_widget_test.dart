import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/create_forum_post_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('retains validation, loading, and server errors', (tester) async {
    final result = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: CreateForumPostDialog(
            channel: _forum,
            onCreate: (_, _, _, _) => result.future,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('create-forum-post-confirm')));
    await tester.pump();
    expect(find.text('Enter a post title.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('forum-post-name')),
      'Native cache',
    );
    await tester.tap(find.byKey(const ValueKey('create-forum-post-confirm')));
    await tester.pump();
    expect(find.text('Write the first message.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('forum-post-content')),
      'SQLite v13 is ready.',
    );
    await tester.tap(find.byKey(const ValueKey('create-forum-post-confirm')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('forum-post-name')))
          .enabled,
      isFalse,
    );

    result.complete(false);
    await tester.pump();
    expect(find.text('Could not create the post.'), findsOneWidget);
  });
}

const _forum = ConversationChannel(
  id: 'forum-1',
  spaceId: 'guild-1',
  name: 'field-reports',
  topic: '',
  kind: ChannelKind.forum,
  availableTags: [ForumTag(id: 'tag-1', name: 'Client', moderated: false)],
  defaultAutoArchiveDurationMinutes: 4320,
);
