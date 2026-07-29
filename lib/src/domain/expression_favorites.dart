/// The GIFs, stickers and emoji an account has starred.
///
/// These live in their own settings blob — `FrecencyUserSettings`, the second
/// of the two `settings-proto` types — rather than in the preloaded one the
/// gateway hands out at `READY`. That is why a fresh session shows an empty
/// favourites tab until the blob has been fetched: nothing in `READY` carries
/// it.
library;

/// How many stickers or emoji Discord will hold.
///
/// The limit is the client's, not the server's: the desktop app refuses the
/// 251st with a notice rather than sending it. Refusing here keeps a write
/// that would be silently dropped, or worse accepted and then truncated on
/// somebody else's client, from going out at all.
const int expressionFavoritesLimit = 250;

/// The ceiling on the encoded `favorite_gifs` group, in bytes.
///
/// GIFs are limited by weight rather than by count, because each one carries a
/// URL of no fixed length. The client measures the serialised group and
/// refuses the addition that would push it over.
const int favoriteGifsMaxBytes = 762880;

/// What kind of media a favourited GIF actually is.
enum FavoriteGifFormat {
  none(0),
  image(1),
  video(2);

  const FavoriteGifFormat(this.code);

  final int code;

  /// An unrecognised code reads as [none] rather than throwing: a blob written
  /// by a newer client must still load, minus the part we cannot draw.
  static FavoriteGifFormat fromCode(int? code) => switch (code) {
    1 => image,
    2 => video,
    _ => none,
  };

  /// What a provider's media type means here.
  ///
  /// Tenor answers with a container name rather than with Discord's enum, and
  /// the two video containers are the ones that decide whether the tile plays
  /// or is drawn as a still.
  static FavoriteGifFormat fromMediaType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('mp4') ||
        lower.contains('webm') ||
        lower.contains('video')) {
      return video;
    }
    return lower.isEmpty ? none : image;
  }
}

/// One starred GIF.
///
/// [url] is the key the blob stores it under, which is the address the picker
/// hands back when the same GIF is unfavourited; [src] is what actually gets
/// played and may differ, since Discord rewrites some sources to a still form.
final class FavoriteGif {
  const FavoriteGif({
    required this.url,
    required this.src,
    this.format = FavoriteGifFormat.none,
    this.width = 0,
    this.height = 0,
    this.order = 0,
  });

  final String url;
  final String src;
  final FavoriteGifFormat format;
  final int width;
  final int height;

  /// Where it sits in the favourites tab. Discord counts upwards, so the
  /// newest addition has the highest number and the tab is shown reversed.
  final int order;

  /// The aspect ratio, or `null` when the blob carried no usable size.
  ///
  /// A grid that divided by a zero height would lay out an infinitely tall
  /// tile, so the absent case is stated rather than defaulted to a square.
  double? get aspectRatio =>
      width > 0 && height > 0 ? width / height : null;

  @override
  bool operator ==(Object other) =>
      other is FavoriteGif &&
      other.url == url &&
      other.src == src &&
      other.format == format &&
      other.width == width &&
      other.height == height &&
      other.order == order;

  @override
  int get hashCode => Object.hash(url, src, format, width, height, order);
}

/// How often one expression has been used.
final class FrecencyScore {
  const FrecencyScore({
    this.totalUses = 0,
    this.score = 0,
    this.recentUses = 0,
  });

  /// Every use ever counted.
  final int totalUses;

  /// What Discord ranks by: uses weighted so that recent ones count for more,
  /// which is why a sticker used twice today outranks one used ten times last
  /// year.
  final int score;

  /// How many timestamps the table still holds. Discord keeps a bounded
  /// window of them, so this is a recency signal rather than a total.
  final int recentUses;
}

/// The frecency table for one kind of expression.
final class ExpressionFrecency {
  const ExpressionFrecency(this._scores);

  final Map<String, FrecencyScore> _scores;

  static const empty = ExpressionFrecency({});

  bool get isEmpty => _scores.isEmpty;

  FrecencyScore? scoreFor(String key) => _scores[key];

  /// [keys] ordered by how often they were used, most first.
  ///
  /// A stable sort, so anything the table says nothing about keeps the order
  /// it arrived in rather than being shuffled by ties.
  List<String> rank(Iterable<String> keys) {
    final ranked = keys.toList();
    ranked.sort((a, b) {
      final left = _scores[a]?.score ?? 0;
      final right = _scores[b]?.score ?? 0;
      return right.compareTo(left);
    });
    return ranked;
  }
}

/// Everything the favourites blob says, as the pickers need it.
final class ExpressionFavorites {
  const ExpressionFavorites({
    this.gifs = const [],
    this.stickerIds = const [],
    this.emojis = const [],
    this.hideGifTooltip = false,
    this.stickerFrecency = ExpressionFrecency.empty,
    this.emojiFrecency = ExpressionFrecency.empty,
  });

  /// Newest first, which is the order the picker shows them in.
  final List<FavoriteGif> gifs;

  final List<String> stickerIds;

  /// Custom emoji are stored by id, unicode ones by their name — `grinning`,
  /// not the character. Discord resolves both through its emoji table, so a
  /// client that stored the surrogates instead would write entries its own
  /// other sessions could not find.
  final List<String> emojis;

  /// Whether the "you can favourite GIFs" hint has been shown its last time.
  /// Discord sets it once three GIFs are starred.
  final bool hideGifTooltip;

  /// How often each sticker has been used, keyed by id.
  final ExpressionFrecency stickerFrecency;

  /// The same for emoji, keyed the way the favourites are: custom ones by id,
  /// unicode ones by name.
  final ExpressionFrecency emojiFrecency;

  static const empty = ExpressionFavorites();

  bool get isEmpty =>
      gifs.isEmpty && stickerIds.isEmpty && emojis.isEmpty;

  bool isFavoriteGif(String url) => gifs.any((gif) => gif.url == url);

  bool isFavoriteSticker(String stickerId) => stickerIds.contains(stickerId);

  bool isFavoriteEmoji(String idOrName) => emojis.contains(idOrName);

  /// The number to give the next GIF, so it sorts above everything held.
  int get nextGifOrder =>
      gifs.isEmpty ? 1 : gifs.map((gif) => gif.order).reduce(_max) + 1;

  bool get canAddSticker => stickerIds.length < expressionFavoritesLimit;

  bool get canAddEmoji => emojis.length < expressionFavoritesLimit;

  ExpressionFavorites copyWith({
    List<FavoriteGif>? gifs,
    List<String>? stickerIds,
    List<String>? emojis,
    bool? hideGifTooltip,
  }) => ExpressionFavorites(
    stickerFrecency: stickerFrecency,
    emojiFrecency: emojiFrecency,
    gifs: gifs ?? this.gifs,
    stickerIds: stickerIds ?? this.stickerIds,
    emojis: emojis ?? this.emojis,
    hideGifTooltip: hideGifTooltip ?? this.hideGifTooltip,
  );

  static int _max(int a, int b) => a > b ? a : b;
}

/// Where the favourites blob is read from and written back to.
///
/// Every write answers `true` when it was taken and `false` when the limit
/// refused it. A refusal is not an error: Discord's own client turns the 251st
/// sticker into a notice rather than a failed request, and the surface needs
/// to tell those two apart.
abstract interface class ExpressionFavoritesRepository {
  /// What is held right now — empty rather than null before the first load, so
  /// a picker can draw before the blob has arrived.
  ExpressionFavorites get current;

  bool get isLoaded;

  Stream<ExpressionFavorites> get updates;

  Future<ExpressionFavorites> load();

  Future<bool> setGifFavorite({
    required FavoriteGif gif,
    required bool favorite,
  });

  Future<bool> setStickerFavorite({
    required String stickerId,
    required bool favorite,
  });

  Future<bool> setEmojiFavorite({
    required String idOrName,
    required bool favorite,
  });
}
