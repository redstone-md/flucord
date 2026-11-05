import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/name_tags.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the middle of a line's capitals sits below the line's top, in
/// Golos Text (ascent 0.98, descent 0.22, cap height 0.70 em) for a line as
/// tall as its [size], with the leading shared evenly.
double _capMiddle(double size) =>
    (size - 1.2 * size) / 2 + (0.98 - 0.70) * size + 0.70 * size / 2;

Future<void> _pump(WidgetTester tester, Widget tag) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    // A tag sits in a row, beside a name.
    home: Scaffold(
      body: Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [tag]),
      ),
    ),
  ),
);

/// The "Clan tag" component in the Flucord Figma file: a 16 px pill, items
/// centred, and the label trimmed to its capitals with 1 px below them, so
/// the capitals' middle sits half a pixel above the pill's.
void main() {
  testWidgets('a clan tag centres its capitals as the component does', (
    tester,
  ) async {
    await _pump(
      tester,
      ClanTagChip(
        clan: const ClanTag(tag: 'CODE', guildId: '1'),
      ),
    );
    final pill = tester.getRect(find.byType(ClanTagChip));
    final label = tester.getRect(find.text('CODE'));
    final mark = tester.getRect(find.byKey(const ValueKey('clan-tag-mark')));

    expect(pill.height, 16);
    expect(mark.size, const Size(8, 8));
    expect(mark.center.dy, closeTo(pill.center.dy, 0.01));
    expect(mark.left - pill.left, 4);
    expect(pill.right - label.right, 5);
    expect(label.left - mark.right, 4);
    expect(label.top + _capMiddle(11), closeTo(pill.center.dy - 0.5, 0.01));
  });

  testWidgets('the APP tag centres its capitals the same way', (tester) async {
    await _pump(tester, const AppTag());
    final pill = tester.getRect(find.byType(AppTag));
    final label = tester.getRect(find.text('APP'));

    expect(label.top + _capMiddle(10), closeTo(pill.center.dy - 0.5, 0.01));
  });
}
