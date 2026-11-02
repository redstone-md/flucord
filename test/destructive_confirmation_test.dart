import 'package:flucord/src/presentation/widgets/destructive_confirmation.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
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

  testWidgets('answers yes only for the named action', (tester) async {
    final answers = await _pumpAsker(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
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
