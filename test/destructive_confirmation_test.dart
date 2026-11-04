import 'package:flucord/src/presentation/widgets/destructive_confirmation.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('names the action on a danger-coloured button', (tester) async {
    await _pumpAsker(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    expect(find.text('Delete #general?'), findsOneWidget);
    expect(find.text('It is gone for everybody.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete'),
    );
    expect(
      button.style?.backgroundColor?.resolve(const {}),
      FlucordTheme.dark.extension<FlucordSurfaceTheme>()!.danger,
    );
  });

  testWidgets('uses the danger colour for the confirm button only', (
    tester,
  ) async {
    await _pumpAsker(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    final danger = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!.danger;
    final dangerFills = find.descendant(
      of: find.byType(Dialog),
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.color == danger,
      ),
    );
    expect(dangerFills, findsOneWidget);
    expect(
      find.descendant(of: dangerFills, matching: find.text('Delete')),
      findsOneWidget,
    );
  });

  testWidgets('titles the dialog in the heading role, with no close button', (
    tester,
  ) async {
    await _pumpAsker(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    final title = tester
        .renderObject<RenderParagraph>(find.text('Delete #general?'))
        .text
        .style!;
    expect(title.fontSize, FlucordTextRole.heading.size);
    expect(title.fontWeight, FontWeight.w500);
    expect(find.byTooltip('Close'), findsNothing);
  });

  testWidgets('shows which keys answer: Esc on Cancel, Enter on the action', (
    tester,
  ) async {
    await _pumpAsker(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    Finder inButton(String label, String key) => find.descendant(
      of: find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
      matching: find.text(key),
    );
    expect(inButton('Cancel', 'Esc'), findsOneWidget);
    expect(inButton('Delete', '↵'), findsOneWidget);
  });

  testWidgets('Escape cancels and Enter confirms', (tester) async {
    final answers = await _pumpAsker(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(answers, [false]);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(answers, [false, true]);
  });

  testWidgets('answers yes only for the named action', (tester) async {
    final answers = await _pumpAsker(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answers, [false]);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(answers, [false, false]);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(destructiveConfirmKey));
    await tester.pumpAndSettle();
    expect(answers, [false, false, true]);
  });
}

Future<List<bool>> _pumpAsker(WidgetTester tester) async {
  final answers = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answers.add(
                await confirmDestructiveAction(
                  context,
                  title: 'Delete #general?',
                  message: 'It is gone for everybody.',
                  confirmLabel: 'Delete',
                ),
              ),
              child: const Text('Ask'),
            ),
          ),
        ),
      ),
    ),
  );
  return answers;
}
