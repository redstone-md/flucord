import 'dart:async';

import 'package:flucord/src/application/gif_picker_controller.dart';
import 'package:flucord/src/data/discord/discord_gif_service.dart';
import 'package:flucord/src/domain/gif_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model', () {
    test('an aspect ratio falls back rather than dividing by zero', () {
      const sized = GifResult(
        id: '1',
        url: 'u',
        previewUrl: 'p',
        width: 200,
        height: 100,
      );
      const unsized = GifResult(id: '1', url: 'u', previewUrl: 'p');

      expect(sized.aspectRatio, 2);
      expect(unsized.aspectRatio, 1);
      expect(sized == sized, isTrue);
      expect(sized == unsized, isFalse);
      expect(sized == Object(), isFalse);
      expect(
        sized.hashCode,
        const GifResult(
          id: '1',
          url: 'u',
          previewUrl: 'p',
          width: 200,
          height: 100,
        ).hashCode,
      );
      expect(const GifTrending().isEmpty, isTrue);
    });
  });

  group('service', () {
    test('reads trending categories and gifs', () async {
      final transport = _FakeTransport(
        trending: {
          'categories': [
            {'name': 'reaction', 'src': 'https://cdn/cat.gif'},
            // No name means no search to run: dropped rather than shown.
            {'src': 'https://cdn/none.gif'},
          ],
          'gifs': [
            {
              'id': 'g1',
              'url': 'https://tenor/view/1',
              'src': 'https://cdn/preview.gif',
              'gif_src': 'https://cdn/full.gif',
              'width': 320,
              'height': 240.6,
              'format': 'gif',
            },
          ],
        },
      );
      final service = DiscordGifService(transport);

      final trending = await service.loadTrending();

      expect(trending.categories.single.name, 'reaction');
      expect(trending.categories.single.previewUrl, 'https://cdn/cat.gif');
      final gif = trending.gifs.single;
      expect(gif.id, 'g1');
      // The full asset is what gets sent; the preview is what the grid draws.
      expect(gif.url, 'https://cdn/full.gif');
      expect(gif.previewUrl, 'https://cdn/preview.gif');
      expect(gif.width, 320);
      expect(gif.height, 241);
      expect(gif.format, 'gif');
      expect(transport.trendingQueries.single, {
        'media_format': 'gif',
        'provider': 'tenor',
      });
    });

    test('a gif with no url cannot be sent and is dropped', () async {
      final transport = _FakeTransport(
        results: [
          {'id': 'g1', 'src': 'https://cdn/preview.gif'},
          {'url': 'https://tenor/view/2'},
        ],
      );
      final service = DiscordGifService(transport);

      final results = await service.search('cat');

      expect(results.single.url, 'https://tenor/view/2');
      // With nothing better to draw, the sendable url stands in.
      expect(results.single.previewUrl, 'https://tenor/view/2');
      // And with no id, the url identifies it.
      expect(results.single.id, 'https://tenor/view/2');
    });

    test('gif_src alone still renders', () async {
      final transport = _FakeTransport(
        results: [
          {'url': 'https://tenor/view/3', 'gif_src': 'https://cdn/full.gif'},
        ],
      );
      final service = DiscordGifService(transport);

      final results = await service.search('dog');

      expect(results.single.previewUrl, 'https://cdn/full.gif');
      expect(results.single.url, 'https://cdn/full.gif');
    });

    test('an empty search is not sent', () async {
      final transport = _FakeTransport();
      final service = DiscordGifService(transport);

      expect(await service.search('   '), isEmpty);
      expect(await service.suggest(''), isEmpty);
      expect(transport.searches, isEmpty);
      expect(transport.suggestions, isEmpty);
    });

    test('suggestions keep only the strings', () async {
      final transport = _FakeTransport(suggestionsPayload: ['cat', 7, null]);
      final service = DiscordGifService(transport);

      expect(await service.suggest(' cat '), ['cat']);
      expect(transport.suggestions.single, 'cat');
    });

    test(
      'a malformed trending payload yields nothing rather than throwing',
      () async {
        final service = DiscordGifService(
          _FakeTransport(trending: {'categories': 7, 'gifs': 'nope'}),
        );

        final trending = await service.loadTrending();

        expect(trending.isEmpty, isTrue);
      },
    );

    test('the provider and format are the service\'s to decide', () async {
      final transport = _FakeTransport();
      final service = DiscordGifService(
        transport,
        mediaFormat: 'mp4',
        provider: 'giphy',
      );

      await service.search('cat');

      expect(transport.searches.single, {
        'q': 'cat',
        'media_format': 'mp4',
        'provider': 'giphy',
      });
    });
  });

  group('controller', () {
    test('a transport with no proxy offers nothing', () async {
      final controller = GifPickerController(() => null);
      addTearDown(controller.dispose);

      await controller.load();
      await controller.searchNow('cat');

      expect(controller.isSupported, isFalse);
      expect(controller.results, isEmpty);
    });

    test('shows trending until something is typed', () async {
      final transport = _FakeTransport(
        trending: {
          'categories': [
            {'name': 'reaction'},
          ],
          'gifs': [
            {'url': 'https://tenor/trending'},
          ],
        },
        results: [
          {'url': 'https://tenor/searched'},
        ],
      );
      final service = DiscordGifService(transport);
      final controller = GifPickerController(
        () => service,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.results.single.url, 'https://tenor/trending');
      expect(controller.categories.single.name, 'reaction');

      await controller.searchNow('cat');
      expect(controller.results.single.url, 'https://tenor/searched');
      // Categories belong to the trending view only.
      expect(controller.categories, isEmpty);

      // A second load is not a second request: trending is already held.
      await controller.load();
      expect(transport.trendingQueries.length, 1);
    });

    test('typing is debounced, and clearing goes straight back', () async {
      final transport = _FakeTransport(
        results: [
          {'url': 'https://tenor/searched'},
        ],
      );
      final service = DiscordGifService(transport);
      final controller = GifPickerController(
        () => service,
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(controller.dispose);

      controller
        ..search('c')
        ..search('ca')
        ..search('cat');
      // Nothing has gone out yet; the box is still being typed into.
      expect(transport.searches, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(transport.searches.single['q'], 'cat');
      expect(controller.results.single.url, 'https://tenor/searched');

      controller.search('');
      expect(controller.results, isEmpty);
      expect(controller.suggestions, isEmpty);
      // Typing the same thing again is not a new search.
      controller.search('');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(transport.searches.length, 1);
    });

    test('a slow earlier search cannot overwrite a later one', () async {
      final slow = Completer<void>();
      final transport = _FakeTransport(
        gate: slow,
        results: [
          {'url': 'https://tenor/first'},
        ],
      );
      final service = DiscordGifService(transport);
      final controller = GifPickerController(
        () => service,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      final first = controller.searchNow('cat');
      transport
        ..gate = null
        ..results = [
          {'url': 'https://tenor/second'},
        ];
      await controller.searchNow('dog');
      expect(controller.results.single.url, 'https://tenor/second');

      slow.complete();
      await first;
      // The stale answer arrived last and was discarded.
      expect(controller.results.single.url, 'https://tenor/second');
      expect(controller.isLoading, isFalse);
    });

    test('a failed search is reported and clears the grid', () async {
      final transport = _FakeTransport(failSearch: true);
      final service = DiscordGifService(transport);
      final controller = GifPickerController(
        () => service,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      await controller.searchNow('cat');

      expect(controller.error, isNotNull);
      expect(controller.results, isEmpty);
      expect(controller.isLoading, isFalse);
    });

    test('a failed trending read is reported', () async {
      final service = DiscordGifService(_FakeTransport(failTrending: true));
      final controller = GifPickerController(() => service);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.error, isNotNull);
      expect(controller.isLoading, isFalse);
    });

    test('a stale failure does not overwrite a newer result', () async {
      final gate = Completer<void>();
      final transport = _FakeTransport(gate: gate, failSearch: true);
      final service = DiscordGifService(transport);
      final controller = GifPickerController(
        () => service,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      final first = controller.searchNow('cat');
      transport
        ..gate = null
        ..failSearch = false
        ..results = [
          {'url': 'https://tenor/second'},
        ];
      await controller.searchNow('dog');

      gate.complete();
      await first;

      expect(controller.error, isNull);
      expect(controller.results.single.url, 'https://tenor/second');
    });

    test('a load already running is not started twice', () async {
      final gate = Completer<void>();
      final transport = _FakeTransport(gate: gate);
      final service = DiscordGifService(transport);
      final controller = GifPickerController(() => service);
      addTearDown(controller.dispose);

      final first = controller.load();
      await controller.load();
      gate.complete();
      await first;

      expect(transport.trendingQueries.length, 1);
    });

    test('swapping the transport forgets what was loaded', () async {
      var transport = _FakeTransport(
        trending: {
          'gifs': [
            {'url': 'https://tenor/old'},
          ],
        },
      );
      var service = DiscordGifService(transport);
      final controller = GifPickerController(() => service);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.results.single.url, 'https://tenor/old');

      transport = _FakeTransport(
        trending: {
          'gifs': [
            {'url': 'https://tenor/new'},
          ],
        },
      );
      service = DiscordGifService(transport);

      expect(controller.isSupported, isTrue);
      await controller.load();
      expect(controller.results.single.url, 'https://tenor/new');
    });
  });
}

final class _FakeTransport implements DiscordGifTransport {
  _FakeTransport({
    this.trending = const {},
    this.results = const [],
    this.suggestionsPayload = const [],
    this.failTrending = false,
    this.failSearch = false,
    this.gate,
  });

  Map<String, Object?> trending;
  List<Map<String, Object?>> results;
  final List<Object?> suggestionsPayload;
  final bool failTrending;
  bool failSearch;
  Completer<void>? gate;

  final List<Map<String, Object?>> trendingQueries = [];
  final List<Map<String, Object?>> searches = [];
  final List<String> suggestions = [];

  @override
  Future<Map<String, Object?>> getTrendingGifs({
    required String mediaFormat,
    required String provider,
  }) async {
    trendingQueries.add({'media_format': mediaFormat, 'provider': provider});
    await gate?.future;
    if (failTrending) throw StateError('unreachable');
    return trending;
  }

  @override
  Future<List<Map<String, Object?>>> searchGifs({
    required String query,
    required String mediaFormat,
    required String provider,
    int limit = 50,
  }) async {
    searches.add({
      'q': query,
      'media_format': mediaFormat,
      'provider': provider,
    });
    await gate?.future;
    if (failSearch) throw StateError('unreachable');
    return results;
  }

  @override
  Future<List<Object?>> suggestGifs({
    required String query,
    int limit = 8,
  }) async {
    suggestions.add(query);
    return suggestionsPayload;
  }
}
