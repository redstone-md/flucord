/// One GIF, as Discord's provider proxy returns it.
///
/// Two urls matter and they are not interchangeable: [previewUrl] is the small
/// looping asset the grid draws, and [url] is what gets sent as a message. A
/// picker that posted the preview would send a thumbnail.
final class GifResult {
  const GifResult({
    required this.id,
    required this.url,
    required this.previewUrl,
    this.width = 0,
    this.height = 0,
    this.format = '',
  });

  final String id;

  /// The link the message carries.
  final String url;

  /// The asset the grid renders.
  final String previewUrl;

  final int width;
  final int height;
  final String format;

  /// Width over height, or 1 when the provider did not say. Used to lay the
  /// grid out without waiting for every image to load.
  double get aspectRatio => width > 0 && height > 0 ? width / height : 1;

  @override
  bool operator ==(Object other) =>
      other is GifResult &&
      other.id == id &&
      other.url == url &&
      other.previewUrl == previewUrl &&
      other.width == width &&
      other.height == height &&
      other.format == format;

  @override
  int get hashCode => Object.hash(id, url, previewUrl, width, height, format);
}

/// One of the tiles Discord shows before anything is typed.
final class GifCategory {
  const GifCategory({required this.name, required this.previewUrl});

  /// The search this tile runs.
  final String name;
  final String previewUrl;
}

/// What the picker shows when nothing has been searched for.
final class GifTrending {
  const GifTrending({this.categories = const [], this.gifs = const []});

  final List<GifCategory> categories;
  final List<GifResult> gifs;

  bool get isEmpty => categories.isEmpty && gifs.isEmpty;
}

/// Discord's GIF provider proxy.
///
/// Deliberately not Tenor or Giphy directly: the desktop client never talks to
/// either, it asks Discord, and Discord decides which provider answers. Going
/// straight to a provider would need an API key this client has no business
/// holding and would not honour the account's own provider setting.
abstract interface class GifRepository {
  /// The categories and GIFs shown before a search.
  Future<GifTrending> loadTrending();

  /// Results for [query].
  Future<List<GifResult>> search(String query);

  /// Search suggestions for a partial [query].
  Future<List<String>> suggest(String query);
}
