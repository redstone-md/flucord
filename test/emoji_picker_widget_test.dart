import 'dart:async';

import 'package:flucord/src/application/expression_favorites_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/expression_favorites.dart';
import 'package:flucord/src/domain/unicode_emoji.dart';
import 'package:flucord/src/presentation/widgets/emoji_picker.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('the catalogue is grouped into categories with tabs', (
    tester,
  ) async {
    await _pumpPanel(tester);
    final bar = find.byKey(const ValueKey('emoji-category-bar'));
    expect(bar, findsOneWidget);
    // Nine unicode groups plus the leading frequently-used tab.
    for (var index = 0; index <= UnicodeEmojiGroup.values.length; index++) {
      expect(find.byKey(ValueKey('emoji-category-$index')), findsOneWidget);
    }

    expect(find.text('FREQUENT'), findsOneWidget);
    expect(find.text('THE FORGE'), findsOneWidget);
    // The other server's section sits below the fold; scrolling reaches it.
    await tester.scrollUntilVisible(
      find.text('NIGHT SHIFT'),
      120,
      scrollable: _gridScrollable(),
    );
    expect(find.text('NIGHT SHIFT'), findsOneWidget);
    // Every tab shows its own group, and the leading tab holds the frequent
    // view; the last group's tab is where the old off-by-one threw.
    const labels = <String>[
      'FREQUENT',
      'SMILEYS & EMOTION',
      'PEOPLE & BODY',
      'ANIMALS & NATURE',
      'FOOD & DRINK',
      'TRAVEL & PLACES',
      'ACTIVITIES',
      'OBJECTS',
      'SYMBOLS',
      'FLAGS',
    ];
    // Every tab renders, the leading one keeps the frequent view, and the
    // flags tab (the old off-by-one's crash) shows its own group's emoji.
    final flag = UnicodeEmojiCatalog.all
        .firstWhere((emoji) => emoji.group == UnicodeEmojiGroup.flags)
        .glyph;
    for (var index = 0; index < labels.length; index++) {
      await tester.tap(find.byKey(ValueKey('emoji-category-$index')));
      await tester.pumpAndSettle();
      final label = labels[index];
      if (index == 0) {
        // The leading view gathers favourites, frequent and servers; with
        // none stored the search field and the catalogue still stand.
        expect(find.byKey(const ValueKey('emoji-search')), findsOneWidget);
      } else if (label == 'FLAGS') {
        expect(find.text(flag), findsWidgets);
      } else {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data != null &&
                label.startsWith(widget.data!),
          ),
          findsWidgets,
        );
      }
    }
    // A second tap on the last tab returns to the leading view, whose head
    // the scroll position has left behind.
    await tester.tap(
      find.byKey(ValueKey('emoji-category-${labels.length - 1}')),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('FREQUENT'),
      _gridScrollable(),
      const Offset(0, 120),
    );
  });

  testWidgets('a skin tone swap replaces the drawn glyph and what is sent', (
    tester,
  ) async {
    final picked = <String>[];
    await _pumpPanel(tester, onSelected: picked.add);

    // The tone bar names the six choices: the base and five tones.
    for (var index = 0; index < 6; index++) {
      expect(find.byKey(ValueKey('emoji-tone-$index')), findsOneWidget);
    }
    await tester.enterText(
      find.byKey(const ValueKey('emoji-search')),
      'thumbsup',
    );
    await tester.pump();
    expect(find.text('👍'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('emoji-tone-5')));
    await tester.pump();
    expect(find.text('👍'), findsNothing);
    expect(find.text('👍🏿'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('emoji-choice-unicode-thumbsup_tone5')),
    );
    expect(picked.single, '👍🏿');
  });

  testWidgets('emoji from other servers appear under their own name', (
    tester,
  ) async {
    final picked = <String>[];
    await _pumpPanel(tester, onSelected: picked.add);

    await tester.enterText(find.byKey(const ValueKey('emoji-search')), 'relay');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('emoji-choice-custom-relay-horn')),
    );
    expect(picked.single, '<:relay_horn:relay-horn>');
  });

  testWidgets('search matches the catalogue by name and keyword', (
    tester,
  ) async {
    await _pumpPanel(tester);
    await tester.enterText(
      find.byKey(const ValueKey('emoji-search')),
      'rocket',
    );
    await tester.pump();

    // The name match leads the keyword matches.
    expect(
      find.byKey(const ValueKey('emoji-choice-unicode-rocket')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('emoji-search')),
      'launch',
    );
    await tester.pump();
    // `launch` is a keyword of the rocket, not its name.
    expect(
      find.byKey(const ValueKey('emoji-choice-unicode-rocket')),
      findsOneWidget,
    );
  });

  testWidgets('a search inside a category that names nothing shows the empty '
      'state', (tester) async {
    await _pumpPanel(tester);
    await tester.tap(find.byKey(const ValueKey('emoji-category-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('emoji-search')),
      'zzz nothing is named this',
    );
    await tester.pump();
    expect(find.text('No emoji found'), findsOneWidget);
  });

  testWidgets('a screen reader picks an emoji, and a search can match none', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final picked = <String>[];
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpPanel(tester, onSelected: picked.add, compact: true);
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
    testWidgets('starred emoji lead the panel, and a search hides them', (
      tester,
    ) async {
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
      // An entry naming an emoji this session cannot see, a custom one from
      // a server the account left, is skipped rather than drawn as a gap.
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

    testWidgets('a right-click stars an emoji and starring again unstars it', (
      tester,
    ) async {
      final store = _FavoritesStore();
      final favorites = ExpressionFavoritesController(() => store);
      addTearDown(favorites.dispose);

      await _pumpFavoritesPanel(tester, favorites);
      final tile = await _revealCustomTile(tester);
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

    testWidgets('a long press does the same, for a touch screen', (
      tester,
    ) async {
      final store = _FavoritesStore();
      final favorites = ExpressionFavoritesController(() => store);
      addTearDown(favorites.dispose);

      await _pumpFavoritesPanel(tester, favorites);
      await _revealCustomTile(tester);
      await tester.longPress(
        find.byKey(const ValueKey('emoji-choice-custom-custom-1')),
      );
      await tester.pumpAndSettle();

      expect(store.emojiWrites.single, ('custom-1', true));
    });

    testWidgets('a picker with no favourites plane offers no starring', (
      tester,
    ) async {
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
              emojiSections: const [],
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

    testWidgets('the frequent section follows the account use table, custom '
        'emoji included', (tester) async {
      final store = _FavoritesStore()
        ..current = const ExpressionFavorites(
          emojiFrecency: ExpressionFrecency({
            'custom-1': FrecencyScore(totalUses: 40, score: 400),
            'zap': FrecencyScore(totalUses: 9, score: 90),
            'bug': FrecencyScore(totalUses: 5, score: 50),
          }),
        );
      final favorites = ExpressionFavoritesController(() => store);
      addTearDown(favorites.dispose);

      await _pumpFavoritesPanel(tester, favorites);
      expect(find.text('FREQUENT'), findsOneWidget);
      // The custom one, by id, outranks the unicode ones, by name.
      final tiles = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('emoji-picker')),
          matching: find.byType(Text),
        ),
      );
      final glyphs = tiles
          .map((text) => text.data)
          .whereType<String>()
          .toList();
      final zap = glyphs.indexOf('⚡');
      final bug = glyphs.indexOf('🐛');
      expect(zap, greaterThan(-1));
      expect(bug, greaterThan(-1));
      expect(zap, lessThan(bug));
      // The front tile of the section is the custom one, by id: the use
      // table ranks it above the unicode names.
      final firstTileKey = tester
          .widgetList<InkWell>(
            find.descendant(
              of: find.byKey(const ValueKey('emoji-grid-scroll')),
              matching: find.byType(InkWell),
            ),
          )
          .first
          .key;
      expect(firstTileKey, const ValueKey('emoji-choice-custom-custom-1'));
    });
  });
}

Finder _gridScrollable() => find.descendant(
  of: find.byKey(const ValueKey('emoji-grid-scroll')),
  matching: find.byType(Scrollable),
);

/// Scrolls the server's first emoji fully into view. One bare
/// `scrollUntilVisible` stops as soon as any pixel of the tile shows, and
/// the half left under the fold eats the tap.
Future<Finder> _revealCustomTile(WidgetTester tester) async {
  final tile = find.byKey(const ValueKey('emoji-choice-custom-custom-1'));
  await tester.scrollUntilVisible(tile, 200, scrollable: _gridScrollable());
  final grid = tester.getRect(_gridScrollable());
  while (tester.getRect(tile).bottom > grid.bottom) {
    await tester.drag(_gridScrollable(), const Offset(0, -40));
    await tester.pump();
  }
  return tile;
}

const _sections = [
  EmojiServerSection(
    spaceName: 'The Forge',
    emoji: [
      GuildEmoji(id: 'custom-1', spaceId: 'forge', name: 'native_signal'),
      GuildEmoji(id: 'forge-spark', spaceId: 'forge', name: 'forge_spark'),
    ],
  ),
  EmojiServerSection(
    spaceName: 'Night Shift',
    emoji: [GuildEmoji(id: 'relay-horn', spaceId: 'night', name: 'relay_horn')],
  ),
];

Future<void> _pumpPanel(
  WidgetTester tester, {
  ValueChanged<String>? onSelected,
  bool compact = false,
}) async {
  if (compact) {
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Center(
          child: EmojiPickerPanel(
            spaceName: 'The Forge',
            emojiSections: _sections,
            onSelected: onSelected ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
        body: Center(
          child: EmojiPickerPanel(
            spaceName: 'The Forge',
            emojiSections: _sections,
            onSelected: (_) {},
            favorites: favorites,
          ),
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
