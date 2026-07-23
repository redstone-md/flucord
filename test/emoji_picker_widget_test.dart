import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/emoji_picker.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('searches guild emoji and inserts its syntax at the caret', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FlucordApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final composer = find.byKey(const ValueKey('message-composer'));
    await tester.enterText(composer, 'AB');
    final textField = tester.widget<TextField>(composer);
    textField.controller!.selection = const TextSelection.collapsed(offset: 1);

    await tester.tap(find.byKey(const ValueKey('open-emoji-picker')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('emoji-picker')), findsOneWidget);
    expect(find.text('The Forge'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('emoji-search')),
      'forge spark',
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('emoji-choice-custom-forge-spark')),
    );
    await tester.pumpAndSettle();

    expect(textField.controller!.text, 'A<:forge_spark:forge-spark>B');
    expect(find.byKey(const ValueKey('emoji-picker')), findsNothing);
  });

  testWidgets('filters Unicode emoji and exposes button semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: EmojiPickerPanel(
            spaceName: 'The Forge',
            customEmojis: const [
              GuildEmoji(
                id: 'custom-1',
                spaceId: 'forge',
                name: 'native_signal',
              ),
            ],
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('emoji-search')),
      'rocket',
    );
    await tester.pump();

    expect(find.bySemanticsLabel('rocket emoji'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('emoji-choice-unicode-rocket')));
    expect(selected, '🚀');
    semantics.dispose();
  });

  testWidgets('keeps the anchored picker inside a compact desktop window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FlucordApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-emoji-picker')));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const ValueKey('emoji-picker')));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(700));
    expect(rect.bottom, lessThanOrEqualTo(700));
    expect(tester.takeException(), isNull);
  });
}
