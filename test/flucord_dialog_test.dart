import 'package:flucord/src/presentation/widgets/flucord_button.dart';
import 'package:flucord/src/presentation/widgets/flucord_dialog.dart';
import 'package:flucord/src/theme/flucord_radius.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Opens [dialog] from a button and collects what each close answered.
  Future<List<Object?>> open(WidgetTester tester, Widget dialog) async {
    final answers = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await showDialog<Object>(
                context: context,
                builder: (_) => dialog,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return answers;
  }

  Finder inButton(String label, String key) => find.descendant(
    of: find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
    matching: find.text(key),
  );

  testWidgets('a confirming action comes after Cancel, each with its key', (
    tester,
  ) async {
    await open(
      tester,
      Builder(
        builder: (context) => FlucordDialog(
          title: const Text('Ban Jack?'),
          confirm: FlucordDialogConfirm(
            label: 'Ban',
            kind: FlucordButtonKind.danger,
            onPressed: () => Navigator.of(context).pop('ban'),
          ),
        ),
      ),
    );

    expect(inButton('Cancel', FlucordKeyHint.escape), findsOneWidget);
    expect(inButton('Ban', FlucordKeyHint.enter), findsOneWidget);
    expect(
      tester.getCenter(find.text('Cancel')).dx,
      lessThan(tester.getCenter(find.text('Ban')).dx),
    );
  });

  testWidgets("the last button's corner is concentric with the dialog's", (
    tester,
  ) async {
    await open(
      tester,
      Builder(
        builder: (context) => FlucordDialog(
          title: const Text('Ban Jack?'),
          confirm: FlucordDialogConfirm(
            label: 'Ban',
            kind: FlucordButtonKind.danger,
            onPressed: () => Navigator.of(context).pop('ban'),
          ),
        ),
      ),
    );

    final footer = tester.getRect(find.byType(FlucordDialogFooter));
    final button = tester.getRect(
      find.ancestor(
        of: find.text('Ban'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    // The same gap below and beside it, and that gap is the dialog's
    // corner less the button's, so both corners share one centre.
    final gap =
        FlucordRadius.overlay.bottomRight.x -
        FlucordRadius.control.bottomRight.x;
    expect(footer.right - button.right, gap);
    expect(footer.bottom - button.bottom, gap);
  });

  testWidgets('Enter presses the confirming action, Cancel answers nothing', (
    tester,
  ) async {
    final answers = await open(
      tester,
      Builder(
        builder: (context) => FlucordDialog(
          title: const Text('Ban Jack?'),
          confirm: FlucordDialogConfirm(
            label: 'Ban',
            onPressed: () => Navigator.of(context).pop('ban'),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(answers, ['ban']);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answers, ['ban', null]);
  });

  testWidgets('Enter does nothing while the confirming action is disabled', (
    tester,
  ) async {
    await open(
      tester,
      const FlucordDialog(
        title: Text('Ban Jack?'),
        confirm: FlucordDialogConfirm(label: 'Ban', onPressed: null),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('Enter in a field of several lines starts a new line', (
    tester,
  ) async {
    final answers = await open(
      tester,
      Builder(
        builder: (context) => FlucordDialog(
          title: const Text('Report'),
          content: const TextField(
            key: ValueKey('reason'),
            autofocus: true,
            maxLines: 4,
          ),
          confirm: FlucordDialogConfirm(
            label: 'Send',
            onPressed: () => Navigator.of(context).pop('sent'),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(answers, isEmpty);
  });

  testWidgets('a busy dialog cannot be cancelled from its button', (
    tester,
  ) async {
    await open(
      tester,
      const FlucordDialog(
        title: Text('Creating'),
        cancelEnabled: false,
        confirm: FlucordDialogConfirm(label: 'Creating', onPressed: null),
      ),
    );

    final cancel = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Cancel'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(cancel.enabled, isFalse);
  });

  testWidgets('a dialog with a single way out shows Cancel with its key', (
    tester,
  ) async {
    final answers = await open(
      tester,
      const FlucordDialog(
        title: Text('Share a screen'),
        actions: [FlucordDialogCancel()],
      ),
    );

    expect(inButton('Cancel', FlucordKeyHint.escape), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answers, [null]);
  });

  testWidgets('a framed dialog takes the same footer and Enter', (
    tester,
  ) async {
    final answers = await open(
      tester,
      Builder(
        builder: (context) => FlucordDialog.frame(
          maxWidth: 400,
          confirm: FlucordDialogConfirm(
            label: 'Forward',
            onPressed: () => Navigator.of(context).pop('sent'),
          ),
          child: const FlucordDialogHeader(title: 'Forward message'),
        ),
      ),
    );

    expect(inButton('Cancel', FlucordKeyHint.escape), findsOneWidget);
    expect(inButton('Forward', FlucordKeyHint.enter), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(answers, ['sent']);
  });

  testWidgets('the title sits as far below the top as it is from the side', (
    tester,
  ) async {
    await open(
      tester,
      const FlucordDialog(
        title: Text('Leave Play&day?'),
        description: 'You will lose its channels.',
      ),
    );

    final dialog = tester.getRect(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );
    final title = tester.getRect(find.text('Leave Play&day?'));
    final capitals =
        title.top + FlucordType.roomAboveCapitals(FlucordTextRole.heading);
    expect(capitals - dialog.top, closeTo(title.left - dialog.left, 0.01));
  });

  testWidgets('a framed dialog header has no close button', (tester) async {
    await open(
      tester,
      const FlucordDialog.frame(
        child: FlucordDialogHeader(title: 'Connections'),
      ),
    );

    expect(find.text('Connections'), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });
}
