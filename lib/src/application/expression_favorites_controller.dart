import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/expression_favorites.dart';

/// Drives the star on a GIF, a sticker or an emoji.
///
/// The favourites blob is not in `READY`, so this loads it the first time a
/// picker asks. Every write answers whether it was taken, and a refusal is
/// held here rather than thrown: hitting the 250 limit is something to say in
/// the picker, not an error to report as a broken session.
final class ExpressionFavoritesController extends ChangeNotifier {
  ExpressionFavoritesController(this._repositoryProvider);

  final ExpressionFavoritesRepository? Function() _repositoryProvider;

  ExpressionFavoritesRepository? _repository;
  StreamSubscription<ExpressionFavorites>? _subscription;
  bool _disposed = false;
  bool _isLoading = false;
  bool _wasRefused = false;
  ExpressionFavorites _favorites = ExpressionFavorites.empty;

  bool get isSupported {
    _bind();
    return _repository != null;
  }

  ExpressionFavorites get favorites {
    _bind();
    return _favorites;
  }

  bool get isLoading => _isLoading;

  /// Whether the last write was turned down by a limit rather than failing.
  bool get wasRefused => _wasRefused;

  bool isFavoriteGif(String url) => favorites.isFavoriteGif(url);

  bool isFavoriteSticker(String stickerId) =>
      favorites.isFavoriteSticker(stickerId);

  bool isFavoriteEmoji(String idOrName) => favorites.isFavoriteEmoji(idOrName);

  /// Fetches the blob if it has not been read yet.
  Future<void> load() async {
    _bind();
    final repository = _repository;
    if (repository == null || repository.isLoaded || _isLoading) return;
    _isLoading = true;
    _notify();
    try {
      _favorites = await repository.load();
    } on Object {
      // A failed read leaves the favourites empty, which is what the pickers
      // already draw. Nothing is lost by staying quiet about it.
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<bool> toggleGif(FavoriteGif gif) {
    final favorite = !isFavoriteGif(gif.url);
    return _write(
      (repository) => repository.setGifFavorite(gif: gif, favorite: favorite),
    );
  }

  Future<bool> toggleSticker(String stickerId) {
    final favorite = !isFavoriteSticker(stickerId);
    return _write(
      (repository) => repository.setStickerFavorite(
        stickerId: stickerId,
        favorite: favorite,
      ),
    );
  }

  Future<bool> toggleEmoji(String idOrName) {
    final favorite = !isFavoriteEmoji(idOrName);
    return _write(
      (repository) =>
          repository.setEmojiFavorite(idOrName: idOrName, favorite: favorite),
    );
  }

  Future<bool> _write(
    Future<bool> Function(ExpressionFavoritesRepository) action,
  ) async {
    _bind();
    final repository = _repository;
    if (repository == null) return false;
    _wasRefused = false;
    final accepted = await action(repository);
    _wasRefused = !accepted;
    _notify();
    return accepted;
  }

  /// Follows the live repository rather than one taken at construction: a
  /// session swap replaces the store, and a controller still holding the old
  /// one would star into an account nobody is signed into.
  void _bind() {
    final repository = _repositoryProvider();
    if (identical(repository, _repository)) return;
    _repository = repository;
    _subscription?.cancel();
    _subscription = null;
    _wasRefused = false;
    _favorites = repository?.current ?? ExpressionFavorites.empty;
    if (repository == null) return;
    _subscription = repository.updates.listen((favorites) {
      _favorites = favorites;
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
