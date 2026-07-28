import 'dart:async';

import 'package:flucord/src/application/gif_picker_controller.dart';
import 'package:flucord/src/domain/gif_picker.dart';
import 'package:flucord/src/presentation/widgets/gif_picker.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    GifPickerController controller,
    List<String> picked,
  ) => tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (_, _) =>
              GifPickerButton(controller: controller, onSelected: picked.add),
        ),
      ),
    ),
  );

  testWidgets('a transport with no proxy shows no button', (tester) async {
    final controller = GifPickerController(() => null);
    addTearDown(controller.dispose);

    await pump(tester, controller, []);

    expect(find.byKey(const ValueKey('gif-picker-open')), findsNothing);
  });

  testWidgets('picks a trending GIF and sends its url', (tester) async {
    final repository = _FakeRepository(
      trending: const GifTrending(
        // A category with artwork draws it behind the label.
        categories: [
          GifCategory(name: 'reaction', previewUrl: 'https://cdn/cat.gif'),
        ],
        gifs: [GifResult(id: 'g1', url: 'https://tenor/full', previewUrl: '')],
      ),
    );
    final controller = GifPickerController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    final picked = <String>[];

    await pump(tester, controller, picked);
    await tester.tap(find.byKey(const ValueKey('gif-picker-open')));
    await tester.pumpAndSettle();

    expect(find.text('reaction'), findsOne);
    await tester.tap(find.byKey(const ValueKey('gif-result-g1')));
    await tester.pumpAndSettle();

    expect(picked, ['https://tenor/full']);
    // Picking closes the sheet: it is a send action, not a browser.
    expect(find.byKey(const ValueKey('gif-search-field')), findsNothing);
  });

  testWidgets('a category runs its search', (tester) async {
    final repository = _FakeRepository(
      trending: const GifTrending(
        categories: [GifCategory(name: 'reaction', previewUrl: '')],
      ),
      results: const [
        GifResult(id: 'g2', url: 'https://tenor/searched', previewUrl: ''),
      ],
    );
    final controller = GifPickerController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    await tester.tap(find.byKey(const ValueKey('gif-picker-open')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('gif-category-reaction')));
    await tester.pumpAndSettle();

    expect(repository.searched, ['reaction']);
    expect(find.byKey(const ValueKey('gif-result-g2')), findsOne);
  });

  testWidgets('typing searches and a suggestion runs immediately', (
    tester,
  ) async {
    final repository = _FakeRepository(
      results: const [
        GifResult(id: 'g3', url: 'https://tenor/typed', previewUrl: ''),
      ],
      suggestions: const ['cat wave'],
    );
    final controller = GifPickerController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    await tester.tap(find.byKey(const ValueKey('gif-picker-open')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('gif-search-field')),
      'cat',
    );
    await tester.pumpAndSettle();

    expect(repository.searched, ['cat']);
    await tester.tap(find.byKey(const ValueKey('gif-suggestion-cat wave')));
    await tester.pumpAndSettle();

    expect(repository.searched, ['cat', 'cat wave']);
  });

  testWidgets('submitting the field searches without waiting', (tester) async {
    final repository = _FakeRepository(
      results: const [
        GifResult(id: 'g4', url: 'https://tenor/submitted', previewUrl: ''),
      ],
    );
    final controller = GifPickerController(
      () => repository,
      debounce: const Duration(seconds: 30),
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    await tester.tap(find.byKey(const ValueKey('gif-picker-open')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('gif-search-field')),
      'dog',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // The debounce is long, but submitting does not wait it out.
    expect(repository.searched, ['dog']);
  });

  testWidgets('nothing to show says so and offers a retry', (tester) async {
    final repository = _FakeRepository();
    final controller = GifPickerController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    await tester.tap(find.byKey(const ValueKey('gif-picker-open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gif-empty')), findsOne);

    repository.trending = const GifTrending(
      gifs: [GifResult(id: 'g5', url: 'https://tenor/late', previewUrl: '')],
    );
    await tester.tap(find.byKey(const ValueKey('gif-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gif-result-g5')), findsOne);
  });

  testWidgets('a failed search says the proxy answered nothing', (
    tester,
  ) async {
    final repository = _FakeRepository(failSearch: true);
    final controller = GifPickerController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    await tester.tap(find.byKey(const ValueKey('gif-picker-open')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('gif-search-field')),
      'cat',
    );
    await tester.pumpAndSettle();

    expect(find.text('Discord did not return any GIFs.'), findsOne);

    // Retrying a search re-runs the query rather than reloading trending.
    repository
      ..failSearch = false
      ..results = const [
        GifResult(id: 'g6', url: 'https://tenor/retried', previewUrl: ''),
      ];
    await tester.tap(find.byKey(const ValueKey('gif-retry')));
    await tester.pumpAndSettle();

    expect(repository.searched, ['cat', 'cat']);
  });

  testWidgets('a read still running shows progress', (tester) async {
    final gate = Completer<void>();
    final repository = _FakeRepository(
      gate: gate,
      trending: const GifTrending(
        gifs: [GifResult(id: 'g7', url: 'https://tenor/late', previewUrl: '')],
      ),
    );
    final controller = GifPickerController(
      () => repository,
      debounce: Duration.zero,
    );
    addTearDown(controller.dispose);

    await pump(tester, controller, []);
    await tester.tap(find.byKey(const ValueKey('gif-picker-open')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('gif-loading')), findsOne);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gif-result-g7')), findsOne);
  });
}

final class _FakeRepository implements GifRepository {
  _FakeRepository({
    this.trending = const GifTrending(),
    this.results = const [],
    this.suggestions = const [],
    this.failSearch = false,
    this.gate,
  });

  GifTrending trending;
  List<GifResult> results;
  final List<String> suggestions;
  bool failSearch;
  final Completer<void>? gate;
  final List<String> searched = [];

  @override
  Future<GifTrending> loadTrending() async {
    await gate?.future;
    return trending;
  }

  @override
  Future<List<GifResult>> search(String query) async {
    searched.add(query);
    await gate?.future;
    if (failSearch) throw StateError('unreachable');
    return results;
  }

  @override
  Future<List<String>> suggest(String query) async => suggestions;
}
