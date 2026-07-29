import 'dart:async';
import 'package:flucord/src/application/expression_favorites_controller.dart';
import 'package:flucord/src/domain/expression_favorites.dart';
import 'package:flutter/gestures.dart';
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
    await tester.pumpWidget(FlucordApp.demo());
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
    await tester.pumpWidget(FlucordApp.demo());
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


    testWidgets('a screen reader picks an emoji, and a search can match none',
        (tester) async {
      final handle = tester.ensureSemantics();
      final picked = <String>[];
      await tester.binding.setSurfaceSize(const Size(500, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
              onSelected: picked.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester.semantics.tap(find.semantics.byLabel('native_signal guild emoji'));
      await tester.pumpAndSettle();
      expect(picked, isNotEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('emoji-search')),
        'nothing is named this',
      );
      await tester.pumpAndSettle();
      expect(find.text('No emoji found'), findsOneWidget);
      handle.dispose();
    });

  group('the favourites row', () {
    testWidgets('starred emoji lead the panel, and a search hides them',
        (tester) async {
      final store = _FavoritesStore()
        ..current = const ExpressionFavorites(
          emojis: ['custom-1', 'rocket', 'from-a-server-we-left'],
        );
      final favorites = ExpressionFavoritesController(() => store);
      addTearDown(favorites.dispose);

      await _pumpFavoritesPanel(tester, favorites);

      // Both the custom one, by id, and the unicode one, by name. Each is
      // drawn twice: once in the favourites row and once where it lives.
      expect(
        find.byKey(const ValueKey('emoji-starred-custom-custom-1')),
        findsWidgets,
      );
      expect(
        find.byKey(const ValueKey('emoji-starred-unicode-rocket')),
        findsWidgets,
      );
      // An entry naming an emoji this session cannot see — a custom one from
      // a server the account left — is skipped rather than drawn as a gap.
      expect(find.text('FAVOURITES'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('FAVOURITES')).dy,
        lessThan(tester.getTopLeft(find.text('FREQUENT')).dy),
      );

      await tester.enterText(
        find.byKey(const ValueKey('emoji-search')),
        'rocket',
      );
      await tester.pumpAndSettle();
      expect(find.text('FAVOURITES'), findsNothing);
    });

    testWidgets('a right-click stars an emoji and starring again unstars it',
        (tester) async {
      final store = _FavoritesStore();
      final favorites = ExpressionFavoritesController(() => store);
      addTearDown(favorites.dispose);

      await _pumpFavoritesPanel(tester, favorites);
      final tile = find.byKey(const ValueKey('emoji-choice-custom-custom-1'));

      final gesture = await tester.startGesture(
        tester.getCenter(tile),
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.emojiWrites.single, ('custom-1', true));

      final again = await tester.startGesture(
        tester.getCenter(tile),
        buttons: kSecondaryButton,
      );
      await again.up();
      await tester.pumpAndSettle();
      expect(store.emojiWrites.last, ('custom-1', false));
    });

    testWidgets('a long press does the same, for a touch screen',
        (tester) async {
      final store = _FavoritesStore();
      final favorites = ExpressionFavoritesController(() => store);
      addTearDown(favorites.dispose);

      await _pumpFavoritesPanel(tester, favorites);
      await tester.longPress(
        find.byKey(const ValueKey('emoji-choice-custom-custom-1')),
      );
      await tester.pumpAndSettle();

      expect(store.emojiWrites.single, ('custom-1', true));
    });

    testWidgets('a picker with no favourites plane offers no starring',
        (tester) async {
      await _pumpFavoritesPanel(tester, null);

      final tile = tester.widget<InkWell>(
        find.byKey(const ValueKey('emoji-choice-custom-custom-1')),
      );

      expect(tile.onSecondaryTap, isNull);
      expect(tile.onLongPress, isNull);
      expect(find.text('FAVOURITES'), findsNothing);
    });

    testWidgets('the button reads the blob when it is opened', (tester) async {
      final store = _FavoritesStore();
      final favorites = ExpressionFavoritesController(() => store);
      addTearDown(favorites.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: EmojiPickerButton(
              spaceName: 'The Forge',
              customEmojis: const [],
              onSelected: (_) {},
              favorites: favorites,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-emoji-picker')));
      await tester.pumpAndSettle();

      expect(store.loads, 1);
    });
  });
}

Future<void> _pumpFavoritesPanel(
  WidgetTester tester,
  ExpressionFavoritesController? favorites,
) async {
  await tester.binding.setSurfaceSize(const Size(500, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: EmojiPickerPanel(
          spaceName: 'The Forge',
          customEmojis: const [
            GuildEmoji(id: 'custom-1', spaceId: 'forge', name: 'native_signal'),
          ],
          onSelected: (_) {},
          favorites: favorites,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FavoritesStore implements ExpressionFavoritesRepository {
  final StreamController<ExpressionFavorites> _updates =
      StreamController.broadcast();
  final List<(String, bool)> emojiWrites = [];
  @override
  ExpressionFavorites current = ExpressionFavorites.empty;
  int loads = 0;

  @override
  bool get isLoaded => loads > 0;

  @override
  Stream<ExpressionFavorites> get updates => _updates.stream;

  @override
  Future<ExpressionFavorites> load() async {
    loads++;
    return current;
  }

  @override
  Future<bool> setEmojiFavorite({
    required String idOrName,
    required bool favorite,
  }) async {
    emojiWrites.add((idOrName, favorite));
    current = current.copyWith(
      emojis: favorite
          ? [...current.emojis, idOrName]
          : [
              for (final held in current.emojis)
                if (held != idOrName) held,
            ],
    );
    _updates.add(current);
    return true;
  }

  @override
  Future<bool> setGifFavorite({
    required FavoriteGif gif,
    required bool favorite,
  }) async => true;

  @override
  Future<bool> setStickerFavorite({
    required String stickerId,
    required bool favorite,
  }) async => true;
}
