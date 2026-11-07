import 'dart:async';

import 'package:flucord/src/domain/stream_captures.dart';
import 'package:flucord/src/presentation/widgets/go_live_source_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_captures.dart';

const _screens = [
  DisplayCapture(index: 0, name: 'Screen 1'),
  DisplayCapture(index: 1, name: 'Screen 2'),
];
const _notes = WindowCapture(handle: 0x2a, name: 'Notes');

Finder _thumbnail(String sourceId) =>
    find.byKey(ValueKey('go-live-thumbnail-$sourceId'));

void main() {
  testWidgets('windows and screens each show their thumbnail', (tester) async {
    await _pump(tester, const [
      ..._screens,
      _notes,
    ], FakeCaptureCatalog(pictured: {'screen:0:0', 'window:42:0'}));

    // Applications first, the way Discord's picker opens.
    expect(find.text('Notes'), findsOneWidget);
    expect(_thumbnail('window:42:0'), findsOneWidget);
    expect(find.text('Screen 1'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('go-live-tab-screens')));
    await tester.pumpAndSettle();

    expect(_thumbnail('screen:0:0'), findsOneWidget);
    // A screen that could not be captured keeps its place, with an icon.
    expect(find.text('Screen 2'), findsOneWidget);
    expect(_thumbnail('screen:1:0'), findsNothing);
  });

  testWidgets('picking a window answers with its source id', (tester) async {
    final picked = await _pump(tester, const [
      ..._screens,
      _notes,
    ], FakeCaptureCatalog());

    await tester.tap(find.byKey(const ValueKey('go-live-source-window:42:0')));
    await tester.pumpAndSettle();

    expect(await picked, 'window:42:0');
  });

  testWidgets('a pick waits until the thumbnails let go of the screens', (
    tester,
  ) async {
    final ready = Completer<void>();
    var answered = false;
    final picked = await _pump(
      tester,
      _screens,
      FakeCaptureCatalog(thumbnailsReady: ready),
    );
    unawaited(picked.then((_) => answered = true));

    await tester.tap(find.byKey(const ValueKey('go-live-source-screen:1:0')));
    await tester.pumpAndSettle();
    expect(answered, isFalse);

    ready.complete();
    await tester.pumpAndSettle();
    expect(await picked, 'screen:1:0');
  });

  testWidgets('without windows there are no tabs, only screens', (
    tester,
  ) async {
    await _pump(tester, _screens, FakeCaptureCatalog());

    expect(find.byKey(const ValueKey('go-live-tab-screens')), findsNothing);
    expect(find.text('Screen 1'), findsOneWidget);
    expect(find.text('Screen 2'), findsOneWidget);
  });

  testWidgets('a machine with no screens says so rather than showing an empty '
      'grid', (tester) async {
    await _pump(tester, const [], FakeCaptureCatalog());

    expect(
      find.text('This machine reported no screen to capture.'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling hands nothing back', (tester) async {
    final picked = await _pump(tester, _screens, FakeCaptureCatalog());

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await picked, isNull);
  });

  testWidgets('one screen and no window is shared without asking', (
    tester,
  ) async {
    final catalog = FakeCaptureCatalog();
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await GoLiveSourceDialog.pick(
              context,
              sources: const [DisplayCapture(index: 0, name: 'Screen 1')],
              thumbnails: catalog.thumbnails,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(picked, 'screen:0:0');
    expect(catalog.asked, isEmpty);
  });
}

/// Opens the picker over [sources] and answers what it was closed with.
Future<Future<String?>> _pump(
  WidgetTester tester,
  List<StreamCapture> sources,
  FakeCaptureCatalog catalog,
) async {
  final picked = Completer<String?>();
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked.complete(
              await showDialog<String>(
                context: context,
                builder: (_) => GoLiveSourceDialog(
                  sources: sources,
                  thumbnails: catalog.thumbnails,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return picked.future;
}
