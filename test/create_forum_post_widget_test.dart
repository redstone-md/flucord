import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/pending_attachment_picker.dart';
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
            onCreate: (_, _, _, _, _) => result.future,
          ),
        ),
      ),
    );

    await _tapConfirm(tester);
    expect(find.text('Enter a post title.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('forum-post-name')),
      'Native cache',
    );
    await _tapConfirm(tester);
    expect(find.text('Write a message or attach a file.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('forum-post-content')),
      'SQLite v13 is ready.',
    );
    await _tapConfirm(tester);
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

  testWidgets('creates an attachment-only starter message', (tester) async {
    List<PendingAttachment>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: CreateForumPostDialog(
            channel: _forum,
            attachmentPicker: const _FakeAttachmentPicker(),
            onCreate: (_, _, attachments, _, _) async {
              submitted = attachments;
              return false;
            },
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('forum-post-name')),
      'Native capture',
    );
    await tester.tap(find.byKey(const ValueKey('forum-post-add-attachments')));
    await tester.pump();
    expect(find.text('capture.png'), findsOneWidget);
    expect(find.text('1/10'), findsOneWidget);

    await _tapConfirm(tester);

    expect(submitted, hasLength(1));
    expect(submitted!.single.path, r'C:\captures\capture.png');
    expect(find.text('Could not create the post.'), findsOneWidget);
  });
}

Future<void> _tapConfirm(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('create-forum-post-confirm'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}

final class _FakeAttachmentPicker implements PendingAttachmentPicker {
  const _FakeAttachmentPicker();

  @override
  Future<List<PendingAttachment>> pick() async => const [
    PendingAttachment(
      name: 'capture.png',
      path: r'C:\captures\capture.png',
      size: 128,
    ),
  ];
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
