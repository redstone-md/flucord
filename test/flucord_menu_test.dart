import 'package:flucord/src/presentation/widgets/flucord_button.dart';
import 'package:flucord/src/presentation/widgets/flucord_menu.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// How strongly the text [label] shows: its colour's alpha times every
  /// fade drawn over it.
  double shownAlpha(WidgetTester tester, String label) {
    final text = find.text(label);
    final paragraph = tester.renderObject<RenderParagraph>(text);
    var alpha = paragraph.text.style!.color!.a;
    for (final fade in tester.widgetList<Opacity>(
      find.ancestor(of: text, matching: find.byType(Opacity)),
    )) {
      alpha *= fade.opacity;
    }
    return alpha;
  }

  Future<void> openMenu(
    WidgetTester tester,
    List<PopupMenuEntry<String>> items, {
    ValueChanged<String>? onSelected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Center(
            child: PopupMenuButton<String>(
              key: const ValueKey('open'),
              itemBuilder: (_) => items,
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
  }

  testWidgets('a disabled row fades as far as a disabled button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: const Scaffold(
          body: FlucordButton(label: 'Button', onPressed: null),
        ),
      ),
    );
    final button = shownAlpha(tester, 'Button');

    await openMenu(tester, const [
      FlucordMenuItem(label: 'Row', value: 'row', enabled: false),
    ]);

    expect(shownAlpha(tester, 'Row'), closeTo(button, 0.001));
  });

  testWidgets('choosing a row closes the menu with its value', (tester) async {
    final chosen = <String>[];
    await openMenu(tester, const [
      FlucordMenuItem(label: 'Copy', value: 'copy'),
      FlucordMenuDivider(),
      FlucordMenuItem(label: 'Delete', value: 'delete', danger: true),
    ], onSelected: chosen.add);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(chosen, ['delete']);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a disabled row cannot be chosen', (tester) async {
    final chosen = <String>[];
    await openMenu(tester, const [
      FlucordMenuItem(label: 'Pin', value: 'pin', enabled: false),
    ], onSelected: chosen.add);

    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();

    expect(chosen, isEmpty);
    expect(find.text('Pin'), findsOneWidget);
  });

  testWidgets('a row is 32 px high and reads as a menu item', (tester) async {
    final semantics = tester.ensureSemantics();
    await openMenu(tester, const [
      FlucordMenuItem(label: 'Copy', value: 'copy'),
    ]);

    expect(
      tester.getSize(find.byType(FlucordMenuItem<String>)).height,
      FlucordMenuItem.rowHeight,
    );
    final row = tester.getSemantics(find.text('Copy'));
    expect(row.role, SemanticsRole.menuItem);
    expect(
      row,
      isSemantics(
        label: 'Copy',
        isButton: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a checkbox row flips and keeps the menu open', (tester) async {
    final changes = <bool>[];
    await openMenu(tester, [
      FlucordMenuCheckbox(label: 'Mute', value: false, onChanged: changes.add),
    ]);

    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();

    expect(changes, [true, false]);
    expect(find.text('Mute'), findsOneWidget);
  });

  testWidgets('a checkbox row reads as a checked menu item', (tester) async {
    final semantics = tester.ensureSemantics();
    await openMenu(tester, [
      FlucordMenuCheckbox(label: 'Mute', value: true, onChanged: (_) {}),
    ]);

    final row = tester.getSemantics(find.text('Mute'));
    expect(row.role, SemanticsRole.menuItemCheckbox);
    expect(row, isSemantics(label: 'Mute', isChecked: true));
    semantics.dispose();
  });

  testWidgets('a slider row shows its percentage and keeps the menu open', (
    tester,
  ) async {
    final changes = <double>[];
    await openMenu(tester, [
      FlucordMenuSlider(
        label: 'User volume',
        value: 1,
        max: 2,
        mark: 1,
        onChanged: changes.add,
      ),
    ]);
    expect(find.text('100%'), findsOneWidget);
    expect(find.byKey(const ValueKey('flucord-menu-slider-mark')), findsOne);

    // Dragged past the end of the track is the maximum.
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pumpAndSettle();

    expect(changes.last, 2);
    expect(find.text('200%'), findsOneWidget);
    expect(find.text('User volume'), findsOneWidget);
  });

  testWidgets('the slider mark sits under the thumb at its value', (
    tester,
  ) async {
    await openMenu(tester, [
      FlucordMenuSlider(
        label: 'User volume',
        value: 1,
        max: 2,
        mark: 1,
        onChanged: (_) {},
      ),
    ]);

    final mark = tester.getCenter(
      find.byKey(const ValueKey('flucord-menu-slider-mark')),
    );
    // At half of the range, the middle of the slider is the mark.
    expect(mark.dx, closeTo(tester.getCenter(find.byType(Slider)).dx, 0.5));
  });
}
