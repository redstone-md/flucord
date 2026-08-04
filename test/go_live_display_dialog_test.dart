import 'package:flucord/src/application/go_live_controller.dart';
import 'package:flucord/src/presentation/widgets/go_live_display_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('picking a screen answers with its capture id', (tester) async {
    GoLiveDisplay? picked;
    await _pump(tester, const [
      GoLiveDisplay(index: 0, name: 'Screen 1'),
      GoLiveDisplay(index: 1, name: 'Screen 2'),
    ], (display) => picked = display);

    await tester.tap(find.byKey(const ValueKey('go-live-display-1')));
    await tester.pumpAndSettle();

    expect(picked?.sourceId, 'screen:1:0');
  });

  testWidgets('a machine with no screens says so rather than showing an empty '
      'grid', (tester) async {
    await _pump(tester, const [], (_) {});

    // No thumbnails anywhere in here: building them means capturing each
    // display, and Windows allows one duplication of an output at a time — a
    // preview held open is what refused the share that followed it.
    expect(
      find.text('This machine reported no screen to capture.'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling hands nothing back', (tester) async {
    var answered = true;
    await _pump(tester, const [GoLiveDisplay(index: 0, name: 'Screen 1')], (
      display,
    ) {
      answered = display != null;
    });

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answered, isFalse);
  });
}

Future<void> _pump(
  WidgetTester tester,
  List<GoLiveDisplay> displays,
  void Function(GoLiveDisplay?) onPicked,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final picked = await showDialog<GoLiveDisplay>(
                context: context,
                builder: (_) => GoLiveDisplayDialog(displays: displays),
              );
              onPicked(picked);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
