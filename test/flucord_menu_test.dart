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
}
