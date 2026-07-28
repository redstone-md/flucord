import '../../domain/gif_picker.dart';

/// The REST surface the GIF picker needs.
abstract interface class DiscordGifTransport {
  /// `GET /gifs/trending`.
  Future<Map<String, Object?>> getTrendingGifs({
    required String mediaFormat,
    required String provider,
  });

  /// `GET /gifs/search`.
  Future<List<Map<String, Object?>>> searchGifs({
    required String query,
    required String mediaFormat,
    required String provider,
    int limit,
  });

  /// `GET /gifs/suggest`.
  Future<List<Object?>> suggestGifs({required String query, int limit});
}

/// GIFs through Discord's own provider proxy.
final class DiscordGifService implements GifRepository {
  DiscordGifService(
    this._transport, {
    this.mediaFormat = 'gif',
    this.provider = 'tenor',
  });

  final DiscordGifTransport _transport;

  /// Which asset variant to ask for. `gif` is the one every surface here can
  /// render; the desktop client also asks for `mp4` and `webm`, which need a
  /// video pipeline the picker does not have.
  final String mediaFormat;

  /// Which provider Discord should answer from.
  final String provider;

  @override
  Future<GifTrending> loadTrending() async {
    final payload = await _transport.getTrendingGifs(
      mediaFormat: mediaFormat,
      provider: provider,
    );
    return GifTrending(
      categories: [
        for (final raw in _objects(payload['categories'])) ?readCategory(raw),
      ],
      gifs: [for (final raw in _objects(payload['gifs'])) ?readGif(raw)],
    );
  }

  @override
  Future<List<GifResult>> search(String query) async {
    final trimmed = query.trim();
    // An empty search would return the whole provider catalogue, which is not
    // what an empty box means.
    if (trimmed.isEmpty) return const [];
    final payload = await _transport.searchGifs(
      query: trimmed,
      mediaFormat: mediaFormat,
      provider: provider,
    );
    return [for (final raw in payload) ?readGif(raw)];
  }

  @override
  Future<List<String>> suggest(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final payload = await _transport.suggestGifs(query: trimmed);
    return payload.whereType<String>().toList(growable: false);
  }

  /// Maps one GIF, skipping anything with no sendable url.
  ///
  /// `src` is the preview and `gif_src` the full asset; a result carrying only
  /// one of them still renders, but one with no `url` cannot be sent and is
  /// dropped rather than shown as a tile that does nothing.
  static GifResult? readGif(Map<String, Object?> payload) {
    final url = payload['url'];
    if (url is! String || url.isEmpty) return null;
    final gifSrc = payload['gif_src'];
    final src = payload['src'];
    final preview = src is String && src.isNotEmpty
        ? src
        : gifSrc is String && gifSrc.isNotEmpty
        ? gifSrc
        : url;
    final id = payload['id'];
    return GifResult(
      id: id is String && id.isNotEmpty ? id : url,
      url: gifSrc is String && gifSrc.isNotEmpty ? gifSrc : url,
      previewUrl: preview,
      width: _int(payload['width']),
      height: _int(payload['height']),
      format: payload['format'] is String ? payload['format']! as String : '',
    );
  }

  /// Maps a trending category, skipping one with no name to search for.
  static GifCategory? readCategory(Map<String, Object?> payload) {
    final name = payload['name'];
    if (name is! String || name.isEmpty) return null;
    final src = payload['src'];
    return GifCategory(name: name, previewUrl: src is String ? src : '');
  }

  static int _int(Object? value) => switch (value) {
    final int number => number,
    final double number => number.round(),
    _ => 0,
  };

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((entry) => entry.cast<String, Object?>())
            .toList(growable: false)
      : const [];
}
