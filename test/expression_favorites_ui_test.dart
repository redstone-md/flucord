import 'dart:async';

import 'package:flucord/src/application/expression_favorites_controller.dart';
import 'package:flucord/src/application/gif_picker_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/expression_favorites.dart';
import 'package:flucord/src/domain/gif_picker.dart';
import 'package:flucord/src/presentation/widgets/expression_favorite_star.dart';
import 'package:flucord/src/presentation/widgets/gif_picker.dart';
import 'package:flucord/src/presentation/widgets/sticker_picker.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the controller', () {
    test('a transport with no favourites plane answers no to everything',
        () async {
      final controller = ExpressionFavoritesController(() => null);
      addTearDown(controller.dispose);

      expect(controller.isSupported, isFalse);
      expect(controller.favorites, ExpressionFavorites.empty);
      await controller.load();

      expect(await controller.toggleGif(_gif('a')), isFalse);
      expect(await controller.toggleSticker('1'), isFalse);
      expect(await controller.toggleEmoji('smile'), isFalse);
    });

    test('the blob is read once and then followed', () async {
      final store = _FakeStore();
      final controller = ExpressionFavoritesController(() => store);
      addTearDown(controller.dispose);

      await controller.load();
      await controller.load();

      expect(store.loads, 1);
      expect(controller.isLoading, isFalse);

      store.publish(const ExpressionFavorites(emojis: ['elsewhere']));
      await Future<void>.delayed(Duration.zero);
      expect(controller.isFavoriteEmoji('elsewhere'), isTrue);
    });

    test('a load that fails leaves the pickers with nothing rather than an error',
        () async {
      final store = _FakeStore()..failLoad = true;
      final controller = ExpressionFavoritesController(() => store);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.favorites.isEmpty, isTrue);
      expect(controller.isLoading, isFalse);
    });

    test('starring flips whichever way it was', () async {
      final store = _FakeStore();
      final controller = ExpressionFavoritesController(() => store);
      addTearDown(controller.dispose);

      expect(await controller.toggleGif(_gif('a')), isTrue);
      expect(store.gifWrites.single.$2, isTrue);
      expect(controller.isFavoriteGif('a'), isTrue);
      await controller.toggleGif(_gif('a'));
      expect(store.gifWrites.last.$2, isFalse);

      await controller.toggleSticker('1');
      expect(store.stickerWrites.single, ('1', true));
      await controller.toggleSticker('1');
      expect(store.stickerWrites.last, ('1', false));

      await controller.toggleEmoji('smile');
      expect(store.emojiWrites.single, ('smile', true));
      await controller.toggleEmoji('smile');
      expect(store.emojiWrites.last, ('smile', false));
    });

    test('a refusal is remembered as a refusal', () async {
      final store = _FakeStore()..accept = false;
      final controller = ExpressionFavoritesController(() => store);
      addTearDown(controller.dispose);

      expect(await controller.toggleSticker('1'), isFalse);
      expect(controller.wasRefused, isTrue);

      store.accept = true;
      expect(await controller.toggleSticker('1'), isTrue);
      expect(controller.wasRefused, isFalse);
    });

    test('a new session replaces the store rather than writing to the old one',
        () async {
      var store = _FakeStore()..current = const ExpressionFavorites(
        emojis: ['first'],
      );
      final controller = ExpressionFavoritesController(() => store);
      addTearDown(controller.dispose);
      expect(controller.favorites.emojis, ['first']);

      store = _FakeStore()..current = const ExpressionFavorites(
        emojis: ['second'],
      );
      expect(controller.favorites.emojis, ['second']);

      // And the signed-out case: nothing held, nothing listened to.
      final gone = ExpressionFavoritesController(() => null);
      addTearDown(gone.dispose);
      expect(gone.favorites.isEmpty, isTrue);
    });

    test('a load already under way is not started twice', () async {
      final store = _FakeStore()..holdLoad = true;
      final controller = ExpressionFavoritesController(() => store);
      addTearDown(controller.dispose);

      final first = controller.load();
      expect(controller.isLoading, isTrue);
      await controller.load();
      store.releaseLoad();
      await first;

      expect(store.loads, 1);
    });
  });

  group('the star', () {
    testWidgets('a transport that holds no favourites draws none',
        (tester) async {
      final controller = ExpressionFavoritesController(() => null);
      addTearDown(controller.dispose);

      await _pumpStar(tester, controller, onPressed: () async => true);

      expect(find.byIcon(Icons.star_border), findsNothing);
    });

    testWidgets('a refusal says why the star did nothing', (tester) async {
      final controller = ExpressionFavoritesController(() => _FakeStore());
      addTearDown(controller.dispose);

      await _pumpStar(tester, controller, onPressed: () async => false);
      await tester.tap(find.byKey(const ValueKey('star')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('favorite-refused')), findsOneWidget);
    });

    testWidgets('a star that was taken says nothing at all', (tester) async {
      final controller = ExpressionFavoritesController(() => _FakeStore());
      addTearDown(controller.dispose);

      await _pumpStar(tester, controller, onPressed: () async => true);
      await tester.tap(find.byKey(const ValueKey('star')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('favorite-refused')), findsNothing);
    });

    testWidgets('a starred item is drawn filled', (tester) async {
      final controller = ExpressionFavoritesController(() => _FakeStore());
      addTearDown(controller.dispose);

      await _pumpStar(
        tester,
        controller,
        isFavorite: true,
        onPressed: () async => true,
      );

      expect(find.byIcon(Icons.star), findsOneWidget);
    });
  });

  group('the GIF picker', () {
    testWidgets('starred GIFs lead the idle grid and can be unstarred',
        (tester) async {
      final store = _FakeStore()
        ..current = ExpressionFavorites(gifs: [_gif('held')]);
      final favorites = ExpressionFavoritesController(() => store);
      addTearDown(favorites.dispose);
      final picker = GifPickerController(() => _StubGifs());
      addTearDown(picker.dispose);
      final sent = <String>[];

      await _pumpGifPicker(tester, picker, favorites, sent.add);

      expect(find.byKey(const ValueKey('gif-favorite-held')), findsOneWidget);

      // The tile sends the GIF it was starred as.
      await tester.tap(find.byKey(const ValueKey('gif-favorite-held')));
      await tester.pumpAndSettle();
      expect(sent, ['held']);

      await tester.tap(
        find.byKey(const ValueKey('gif-favorite-star-held')),
      );
      await tester.pumpAndSettle();
      expect(store.gifWrites.single, ('held', false));
      // Unstarred, so it leaves the tab it was drawn in.
      expect(find.byKey(const ValueKey('gif-favorite-held')), findsNothing);
    });

    testWidgets('a search result can be starred, and a search hides the tab',
        (tester) async {
      final store = _FakeStore()
        ..current = ExpressionFavorites(gifs: [_gif('held')]);
      final favorites = ExpressionFavoritesController(() => store);
      addTearDown(favorites.dispose);
      final picker = GifPickerController(
        () => _StubGifs(),
        debounce: Duration.zero,
      );
      addTearDown(picker.dispose);

      await _pumpGifPicker(tester, picker, favorites, (_) {});
      await tester.tap(find.byKey(const ValueKey('gif-star-result-1')));
      await tester.pumpAndSettle();

      expect(store.gifWrites.single.$1, 'https://tenor.example/1.gif');
      expect(store.gifWrites.single.$2, isTrue);

      await tester.enterText(
        find.byKey(const ValueKey('gif-search-field')),
        'cats',
      );
      await tester.pumpAndSettle();

      // A search answers about Tenor, so what was starred is out of the way.
      expect(find.byKey(const ValueKey('gif-favorite-held')), findsNothing);
    });

    testWidgets('a picker with no favourites plane still works', (tester) async {
      final picker = GifPickerController(() => _StubGifs());
      addTearDown(picker.dispose);

      await _pumpGifPicker(tester, picker, null, (_) {});

      expect(find.byKey(const ValueKey('gif-result-result-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('gif-star-result-1')), findsNothing);
    });
  });

  group('the sticker picker', () {
    testWidgets('a sticker is starred, and starred ones come first',
        (tester) async {
      final store = _FakeStore()
        ..current = const ExpressionFavorites(stickerIds: ['s2']);
      final favorites = ExpressionFavoritesController(() => store);
      addTearDown(favorites.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: StickerPickerButton(
              stickers: [
                _sticker('s1', 'first'),
                _sticker('s2', 'second'),
              ],
              isSending: false,
              onSend: (_) async => true,
              favorites: favorites,
              assetBuilder: (_, item) => Text(item.name),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-sticker-picker')));
      await tester.pumpAndSettle();

      // The starred one is drawn above the other.
      final positions = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .where((label) => label == 'first' || label == 'second')
          .toList();
      expect(positions.first, 'second');

      await tester.tap(find.byKey(const ValueKey('sticker-star-s1')));
      await tester.pumpAndSettle();
      expect(store.stickerWrites.single, ('s1', true));
      expect(store.loads, 1);
    });

    testWidgets('the button closes what it opened, and says when nothing '
        'matched', (tester) async {
      final favorites = ExpressionFavoritesController(() => _FakeStore());
      addTearDown(favorites.dispose);
      final handle = tester.ensureSemantics();
      await _pumpStickerPicker(tester, favorites: favorites);

      await tester.tap(find.byKey(const ValueKey('open-sticker-picker')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sticker-search')),
        'nothing named this',
      );
      await tester.pumpAndSettle();
      expect(find.text('No stickers found'), findsOneWidget);

      // A screen reader picks the sticker the same way a click does.
      await tester.enterText(find.byKey(const ValueKey('sticker-search')), '');
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('first'));
      await tester.pumpAndSettle();
      expect(find.text('1/3 selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open-sticker-picker')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sticker-picker')), findsNothing);
      handle.dispose();
    });

    testWidgets('a composer with no favourites plane draws no stars',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: StickerPickerButton(
              stickers: [
                _sticker('s1', 'first'),
              ],
              isSending: false,
              onSend: (_) async => true,
              assetBuilder: (_, item) => Text(item.name),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-sticker-picker')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sticker-star-s1')), findsNothing);
    });
  });
}

FavoriteGif _gif(String url) => FavoriteGif(url: url, src: url, order: 1);

Future<void> _pumpStickerPicker(
  WidgetTester tester, {
  ExpressionFavoritesController? favorites,
}) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: StickerPickerButton(
        stickers: [_sticker('s1', 'first')],
        isSending: false,
        onSend: (_) async => true,
        favorites: favorites,
        assetBuilder: (_, item) => Text(item.name),
      ),
    ),
  ),
);

GuildSticker _sticker(String id, String name) => GuildSticker(
  item: MessageSticker(
    id: id,
    name: name,
    format: StickerFormat.png,
    url: 'https://cdn.example/$id.png',
  ),
  spaceId: 'guild-1',
  tags: const [],
  available: true,
);

Future<void> _pumpStar(
  WidgetTester tester,
  ExpressionFavoritesController controller, {
  required Future<bool> Function() onPressed,
  bool isFavorite = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: ExpressionFavoriteStar(
        key: const ValueKey('star'),
        controller: controller,
        isFavorite: isFavorite,
        onPressed: onPressed,
      ),
    ),
  ),
);

Future<void> _pumpGifPicker(
  WidgetTester tester,
  GifPickerController picker,
  ExpressionFavoritesController? favorites,
  ValueChanged<String> onSelected,
) async {
  await tester.binding.setSurfaceSize(const Size(600, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: GifPickerSheet(
          controller: picker,
          onSelected: onSelected,
          favorites: favorites,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _StubGifs implements GifRepository {
  @override
  Future<GifTrending> loadTrending() async => const GifTrending(
    gifs: [
      GifResult(
        id: 'result-1',
        url: 'https://tenor.example/1.gif',
        previewUrl: 'https://tenor.example/1.png',
        width: 200,
        height: 100,
        format: 'gif',
      ),
    ],
  );

  @override
  Future<List<GifResult>> search(String query) async => const [];

  @override
  Future<List<String>> suggest(String query) async => const [];
}

final class _FakeStore implements ExpressionFavoritesRepository {
  final StreamController<ExpressionFavorites> _updates =
      StreamController.broadcast();
  final List<(String, bool)> gifWrites = [];
  final List<(String, bool)> stickerWrites = [];
  final List<(String, bool)> emojiWrites = [];
  @override
  ExpressionFavorites current = ExpressionFavorites.empty;
  int loads = 0;
  bool accept = true;
  bool failLoad = false;
  bool holdLoad = false;
  Completer<void>? _held;

  void publish(ExpressionFavorites favorites) {
    current = favorites;
    _updates.add(favorites);
  }

  void releaseLoad() => _held?.complete();

  @override
  bool get isLoaded => loads > 0;

  @override
  Stream<ExpressionFavorites> get updates => _updates.stream;

  @override
  Future<ExpressionFavorites> load() async {
    loads++;
    if (holdLoad) {
      final held = _held = Completer<void>();
      await held.future;
    }
    if (failLoad) throw StateError('load failed');
    return current;
  }

  @override
  Future<bool> setGifFavorite({
    required FavoriteGif gif,
    required bool favorite,
  }) async {
    gifWrites.add((gif.url, favorite));
    if (!accept) return false;
    publish(
      current.copyWith(
        gifs: favorite
            ? [...current.gifs, gif]
            : [
                for (final held in current.gifs)
                  if (held.url != gif.url) held,
              ],
      ),
    );
    return true;
  }

  @override
  Future<bool> setStickerFavorite({
    required String stickerId,
    required bool favorite,
  }) async {
    stickerWrites.add((stickerId, favorite));
    if (!accept) return false;
    publish(
      current.copyWith(
        stickerIds: favorite
            ? [...current.stickerIds, stickerId]
            : [
                for (final held in current.stickerIds)
                  if (held != stickerId) held,
              ],
      ),
    );
    return true;
  }

  @override
  Future<bool> setEmojiFavorite({
    required String idOrName,
    required bool favorite,
  }) async {
    emojiWrites.add((idOrName, favorite));
    if (!accept) return false;
    publish(
      current.copyWith(
        emojis: favorite
            ? [...current.emojis, idOrName]
            : [
                for (final held in current.emojis)
                  if (held != idOrName) held,
              ],
      ),
    );
    return true;
  }
}
