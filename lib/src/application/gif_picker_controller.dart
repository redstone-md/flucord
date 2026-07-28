import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/gif_picker.dart';

/// Drives the GIF picker.
///
/// Typing runs a search, so the query is debounced: every keystroke reaching
/// the provider would spend a request per character and return results for a
/// prefix nobody meant to search for.
final class GifPickerController extends ChangeNotifier {
  GifPickerController(
    this._repositoryProvider, {
    this.debounce = const Duration(milliseconds: 320),
  });

  final GifRepository? Function() _repositoryProvider;

  /// How long typing has to stop before a search goes out.
  final Duration debounce;

  GifRepository? _repository;
  Timer? _debounce;
  bool _bound = false;
  bool _disposed = false;

  String _query = '';
  GifTrending _trending = const GifTrending();
  List<GifResult> _results = const [];
  List<String> _suggestions = const [];
  bool _isLoading = false;
  Object? _error;
  int _generation = 0;

  bool get isSupported {
    _bind();
    return _repository != null;
  }

  String get query => _query;

  /// What the grid shows: search results once something was typed, otherwise
  /// whatever is trending.
  List<GifResult> get results =>
      _query.trim().isEmpty ? _trending.gifs : _results;

  List<GifCategory> get categories =>
      _query.trim().isEmpty ? _trending.categories : const [];

  List<String> get suggestions => _suggestions;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  /// Reads the trending set, unless it is already held.
  Future<void> load() async {
    _bind();
    final repository = _repository;
    if (repository == null || _isLoading || !_trending.isEmpty) return;
    _isLoading = true;
    _error = null;
    _notify();
    try {
      _trending = await repository.loadTrending();
    } on Object catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Types into the search box.
  void search(String query) {
    _bind();
    if (_query == query) return;
    _query = query;
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      // Clearing the box goes straight back to trending rather than waiting
      // out a debounce for a search that will not run.
      _results = const [];
      _suggestions = const [];
      _error = null;
      _notify();
      return;
    }
    _notify();
    _debounce = Timer(debounce, () => unawaited(_run(query)));
  }

  /// Runs [query] now, as picking a category or a suggestion does.
  Future<void> searchNow(String query) async {
    _bind();
    _debounce?.cancel();
    _query = query;
    _notify();
    await _run(query);
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    super.dispose();
  }

  Future<void> _run(String query) async {
    final repository = _repository;
    if (repository == null) return;
    final generation = ++_generation;
    _isLoading = true;
    _error = null;
    _notify();
    try {
      final results = await repository.search(query);
      final suggestions = await repository.suggest(query);
      // A slower earlier search must not overwrite a later one's results.
      if (generation != _generation) return;
      _results = results;
      _suggestions = suggestions;
    } on Object catch (error) {
      if (generation != _generation) return;
      _error = error;
      _results = const [];
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        _notify();
      }
    }
  }

  bool _bind() {
    final repository = _repositoryProvider();
    if (_bound && identical(repository, _repository)) return false;
    _bound = true;
    _repository = repository;
    _trending = const GifTrending();
    _results = const [];
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
