import 'package:flucord/src/presentation/widgets/flucord_controls.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: child,
          ),
        ),
      ),
    ),
  );

  group('a text field', () {
    testWidgets('has its label above a 36 px field', (tester) async {
      await pump(tester, const FlucordTextField(label: 'Server name'));

      expect(find.text('Server name'), findsOneWidget);
      expect(tester.getSize(find.byType(TextField)).height, 36);
      expect(
        tester.getBottomLeft(find.text('Server name')).dy,
        lessThan(tester.getTopLeft(find.byType(TextField)).dy),
      );
    });

    testWidgets('shows the focus ring when focused', (tester) async {
      await pump(tester, const FlucordTextField(label: 'Server name'));

      InputDecorator decorator() =>
          tester.widget<InputDecorator>(find.byType(InputDecorator));
      expect(decorator().isFocused, isFalse);

      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(decorator().isFocused, isTrue);
      final ring = Theme.of(
        tester.element(find.byType(TextField)),
      ).inputDecorationTheme.focusedBorder!.borderSide;
      expect(ring, BorderSide(color: surfaces.focusRing, width: 2));
    });

    testWidgets('names an error under the field in the error colour', (
      tester,
    ) async {
      await pump(
        tester,
        const FlucordTextField(
          label: 'Server name',
          errorText: 'Give the server a name.',
        ),
      );

      final error = tester.widget<Text>(find.text('Give the server a name.'));
      expect(
        error.style?.color ?? DefaultTextStyle.of(
          tester.element(find.text('Give the server a name.')),
        ).style.color,
        surfaces.errorText,
      );
    });

    testWidgets('is 88 px high when it takes several lines', (tester) async {
      await pump(
        tester,
        const FlucordTextField(label: 'About me', multiline: true),
      );

      expect(tester.getSize(find.byType(TextField)).height, 88);
    });
  });

  group('a toggle', () {
    testWidgets('is a 32 by 18 pill that flips on tap, and on Space once tabbed to', (
      tester,
    ) async {
      var value = false;
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => FlucordToggle(
            value: value,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      );

      expect(tester.getSize(find.byType(FlucordToggle)), const Size(32, 18));
      expect(
        tester.getSemantics(find.byType(FlucordToggle)),
        matchesSemantics(
          hasToggledState: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      await tester.tap(find.byType(FlucordToggle));
      await tester.pump();
      expect(value, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(value, isFalse);
    });

    testWidgets('without a handler it shows the value and cannot change', (
      tester,
    ) async {
      await pump(tester, const FlucordToggle(value: true));

      await tester.tap(find.byType(FlucordToggle));
      await tester.pump();

      expect(
        tester.getSemantics(find.byType(FlucordToggle)),
        matchesSemantics(
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
        ),
      );
    });
  });

  group('a segmented group', () {
    testWidgets('selects the option tapped, each 28 px high', (tester) async {
      var selected = 'Online';
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => FlucordSegmented<String>(
            options: const [
              FlucordSegment('Online', 'Online'),
              FlucordSegment('All', 'All'),
            ],
            selected: selected,
            onSelected: (value) => setState(() => selected = value),
          ),
        ),
      );

      expect(tester.getSize(find.byType(FlucordTab).first).height, 28);
      await tester.tap(find.text('All'));
      await tester.pump();

      expect(selected, 'All');
      expect(
        tester.getSemantics(find.widgetWithText(FlucordTab, 'All')),
        containsSemantics(isSelected: true, isButton: true),
      );
    });
  });

  group('a select', () {
    testWidgets('shows the chosen item with a chevron and changes it', (
      tester,
    ) async {
      String? chosen = 'a';
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => FlucordSelect<String>(
            label: 'Input device',
            value: chosen,
            items: const [('a', 'Built-in mic'), ('b', 'Headset')],
            onChanged: (value) => setState(() => chosen = value),
          ),
        ),
      );

      expect(find.text('Input device'), findsOneWidget);
      expect(find.text('Built-in mic'), findsOneWidget);

      await tester.tap(find.text('Built-in mic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Headset').last);
      await tester.pumpAndSettle();

      expect(chosen, 'b');
    });
  });
}
