import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/pending_attachment_picker.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

/// The composer's honesty checks: the character count near the limit, the
/// upload limit stated before a file is sent, and the spoiler tag that
/// travels with the file. Driven the way the app drives the composer: files
/// through the picker seam, text through the box, and the answers read off
/// what the composer sends and shows.
void main() {
  testWidgets('stays silent until the limit is near, then counts down', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'a' * 100,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('composer-character-counter')),
      findsNothing,
      reason: 'a hundred of two thousand characters is nowhere near the limit',
    );

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'a' * 1901,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('composer-character-counter')),
      findsOneWidget,
    );
    expect(find.text('99'), findsOneWidget);
  });

  testWidgets('an over-limit message shows a red count and refuses to send', (
    tester,
  ) async {
    String? sentBody;
    await _pump(
      tester,
      onSend: (body, _, _, _) async {
        sentBody = body;
        return true;
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'a' * 2001,
    );
    await tester.pump();

    expect(find.text('-1'), findsOneWidget);
    expect(find.text('Your message is above the limit.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('send-message')));
    await tester.pumpAndSettle();

    expect(sentBody, isNull, reason: 'nothing over the limit leaves the box');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('message-composer')))
          .controller
          ?.text,
      'a' * 2001,
      reason: 'the words stay for the user to shorten',
    );
  });

  testWidgets('counts characters, not the halves emoji split into', (
    tester,
  ) async {
    await _pump(tester, characterLimit: 10);

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'ab \u{1F600} cd',
    );
    await tester.pump();

    // Two letters, one emoji, two letters, two spaces: seven characters.
    expect(
      find.byKey(const ValueKey('composer-character-counter')),
      findsOneWidget,
    );
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('a file above the limit is refused before it is attached', (
    tester,
  ) async {
    final picker = _FixedPicker([
      PendingAttachment(name: 'small.txt', path: '/tmp/small.txt', size: 12),
      PendingAttachment(
        name: 'huge.bin',
        path: '/tmp/huge.bin',
        size: 40 * 1024 * 1024,
      ),
    ]);
    await _pump(
      tester,
      attachmentSizeLimitBytes: 20 * 1024 * 1024,
      picker: picker,
    );

    await tester.tap(find.byKey(const ValueKey('add-attachment')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pending-attachment-/tmp/small.txt')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pending-attachment-/tmp/huge.bin')),
      findsNothing,
      reason: 'the refused file never reaches the strip',
    );
    expect(find.textContaining('above the 20 MB upload limit'), findsOneWidget);
  });

  testWidgets('a transport that has not stated a limit takes every file', (
    tester,
  ) async {
    final picker = _FixedPicker([
      PendingAttachment(
        name: 'huge.bin',
        path: '/tmp/huge.bin',
        size: 40 * 1024 * 1024,
      ),
    ]);
    await _pump(tester, attachmentSizeLimitBytes: null, picker: picker);

    await tester.tap(find.byKey(const ValueKey('add-attachment')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pending-attachment-/tmp/huge.bin')),
      findsOneWidget,
    );
  });

  testWidgets('tagging a file as a spoiler renames it on the way out', (
    tester,
  ) async {
    final sent = <List<PendingAttachment>>[];
    await _pump(
      tester,
      picker: _FixedPicker([
        PendingAttachment(name: 'cat.png', path: '/tmp/cat.png', size: 12),
      ]),
      onSend: (body, attachments, _, _) async {
        sent.add(attachments);
        return true;
      },
    );

    await tester.tap(find.byKey(const ValueKey('add-attachment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-spoiler-/tmp/cat.png')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('message-composer')),
      'a surprise',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-message')));
    await tester.pumpAndSettle();

    expect(
      sent.single.single.name,
      'SPOILER_cat.png',
      reason: 'the prefix is the tag, and it rides the filename',
    );
    expect(sent.single.single.isSpoiler, isTrue);
  });

  testWidgets('an already-tagged spoiler file can be untagged', (tester) async {
    final picker = _FixedPicker([
      PendingAttachment(
        name: 'SPOILER_cat.png',
        path: '/tmp/cat.png',
        size: 12,
      ),
    ]);
    await _pump(tester, picker: picker);

    await tester.tap(find.byKey(const ValueKey('add-attachment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-spoiler-/tmp/cat.png')));
    await tester.pumpAndSettle();

    expect(
      find.text('cat.png'),
      findsOneWidget,
      reason: 'the strip shows the name the receiver will store',
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  int characterLimit = 2000,
  int? attachmentSizeLimitBytes,
  PendingAttachmentPicker? picker,
  SendMessageCallback? onSend,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: MessageComposer(
          channelId: 'general',
          channelName: 'general',
          spaceName: 'The Forge',
          emojiSections: const [],
          stickerSections: const [],
          isSending: false,
          characterLimit: characterLimit,
          attachmentSizeLimitBytes: attachmentSizeLimitBytes,
          attachmentPicker:
              picker ?? const _FixedPicker([]) as PendingAttachmentPicker,
          onSend: onSend ?? (_, _, _, _) async => true,
          onCreatePoll: (_) async => true,
          onSendStickers: (_) async => true,
          onCancelReply: () {},
          onTyping: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FixedPicker implements PendingAttachmentPicker {
  const _FixedPicker(this.files);

  final List<PendingAttachment> files;

  @override
  Future<List<PendingAttachment>> pick() async => files;
}
