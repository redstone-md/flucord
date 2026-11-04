import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/composer_draft.dart';
import 'package:flucord/src/presentation/widgets/message_composer.dart';
import 'package:flucord/src/theme/flucord_icons.dart';
import 'package:flucord/src/theme/flucord_radius.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';

import 'support/flucord_icon_finder.dart';

/// The composer reads as the place to type: a recessed 44 px box with 16 px
/// around it, the attach button on the left and the expression buttons on
/// the right, all 28 px.
void main() {
  final surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;
  final field = find.byKey(const ValueKey('message-composer'));
  const hint = 'Message #general';

  InputDecoration decorationOf(WidgetTester tester) => tester
      .widget<InputDecorator>(
        find.descendant(of: field, matching: find.byType(InputDecorator)),
      )
      .decoration;

  testWidgets('is a 44 px recessed box with 16 px around it', (tester) async {
    await _pump(tester);

    final box = tester.getRect(field);
    final composer = tester.getRect(find.byType(MessageComposer));
    expect(box.height, 44);
    expect(box.left - composer.left, 16);
    expect(composer.right - box.right, 16);
    expect(composer.bottom - box.bottom, 16);

    final decoration = decorationOf(tester);
    expect(decoration.fillColor, surfaces.inset);
    expect(
      decoration.enabledBorder,
      OutlineInputBorder(
        borderRadius: FlucordRadius.medium,
        borderSide: BorderSide(color: surfaces.border),
      ),
    );
  });

  testWidgets('grows with its text', (tester) async {
    await _pump(tester);

    await tester.enterText(field, 'one\ntwo\nthree');
    await tester.pump();

    expect(tester.getSize(field).height, greaterThan(44));
  });

  testWidgets('shows the hint in the caption tier and text in the body role', (
    tester,
  ) async {
    await _pump(tester);

    final hintStyle = tester
        .renderObject<RenderParagraph>(find.text(hint))
        .text
        .style!;
    expect(hintStyle.color, surfaces.captionText);
    expect(hintStyle.fontSize, FlucordType.body);

    final typed = tester.widget<EditableText>(find.byType(EditableText)).style;
    expect(typed.fontSize, FlucordType.body);
    expect(typed.height, FlucordTextRole.body.style.height);
  });

  testWidgets('attaches on the left and keeps emoji and send on the right', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(field, 'hello');
    await tester.pump();

    final box = tester.getRect(field);
    final attach = find.byKey(const ValueKey('composer-menu'));
    final emoji = find.byKey(const ValueKey('open-emoji-picker'));
    final send = find.byKey(const ValueKey('send-message'));

    expect(tester.getCenter(attach).dx, lessThan(box.center.dx));
    expect(tester.getCenter(emoji).dx, greaterThan(box.center.dx));
    for (final (button, icon) in [
      (attach, FlucordIcons.attach),
      (emoji, FlucordIcons.emoji),
      (send, FlucordIcons.send),
    ]) {
      expect(tester.getSize(button), const Size.square(28));
      expect(
        find.descendant(of: button, matching: findFlucordIcon(icon)),
        findsOneWidget,
      );
    }
  });
}

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MessageComposer(
            drafts: MemoryComposerDraftStore(),
            channelId: 'general',
            channelName: 'general',
            spaceName: 'The Forge',
            emojiSections: const [],
            stickerSections: const [],
            isSending: false,
            onSend: (_, _, _, _) async => true,
            onCreatePoll: (_) async => true,
            onSendStickers: (_) async => true,
            onCancelReply: () {},
            onTyping: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
