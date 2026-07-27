import 'package:flutter/foundation.dart';

import '../domain/message_search.dart';
import '../domain/message_search_repository.dart';
import 'message_search_grammar.dart';

enum MessageSearchStatus {
  /// No search has been asked for, or the last one was cleared.
  idle,
  searching,

  /// The server is still building the index for this corpus. Not an error and
  /// not an empty result — a state the surface has to name out loud.
  indexing,
  ready,
  failed,
}

/// Drives one server-side search and the page the reader is looking at.
///
/// The repository is resolved on every call rather than held, because the
/// transport is replaced whenever the session changes; a controller holding the
/// old one would keep searching an account that has signed out.
final class MessageSearchController extends ChangeNotifier {
  MessageSearchController(this._repositoryProvider);

  final MessageSearchRepository? Function() _repositoryProvider;

  MessageSearchScope? _scope;
  MessageSearchQuery? _query;
  MessageSearchResults? _results;
  MessageSearchIndexing? _indexing;
  MessageSearchStatus _status = MessageSearchStatus.idle;
  Object? _error;
  String _text = '';
  List<String> _unresolved = const [];

  /// Survives an empty result set and a cleared bar, so the reader's chosen
  /// order still applies to the next thing they search for.
  MessageSearchSort _sort = MessageSearchSort.newest;

  /// Bumped for every search so a page that arrives after the reader moved on
  /// cannot overwrite the page they are actually looking at.
  int _generation = 0;
  bool _disposed = false;

  /// Whether the signed-in transport can search at all.
  bool get isSupported => _repositoryProvider() != null;

  MessageSearchStatus get status => _status;
  MessageSearchResults? get results => _results;
  MessageSearchIndexing? get indexing => _indexing;
  Object? get error => _error;

  /// The text the current results answer, kept so the panel can echo it.
  String get text => _text;
  List<String> get unresolved => _unresolved;
  MessageSearchSort get sort => _sort;
  int get pageIndex => _query?.pageIndex ?? 0;
  int get pageCount => _results?.pageCount ?? 0;

  /// Whether the last submitted text carried a filter the server could be
  /// asked about. False for a line that was only unresolvable filters.
  bool get hasQuery => _query != null;

  /// Runs [text] against [scope].
  ///
  /// A line that resolves to no parameters at all is refused rather than sent:
  /// an empty query asks the server for every message in the corpus, which is
  /// not what an empty search bar means.
  Future<void> search({
    required MessageSearchScope scope,
    required String text,
    required MessageSearchGrammar grammar,
  }) async {
    final parse = grammar.parse(text);
    _text = text;
    _unresolved = parse.unresolved;
    if (parse.isEmpty) {
      _cancelActive();
      _scope = scope;
      _query = null;
      _results = null;
      _indexing = null;
      _error = null;
      _status = MessageSearchStatus.idle;
      notifyListeners();
      return;
    }
    _scope = scope;
    await _run(MessageSearchQuery(filters: parse.filters, sort: _sort));
  }

  /// Re-runs the current query — after a failure, or while the server is still
  /// indexing and the reader wants to try again sooner.
  Future<void> retry() async {
    final query = _query;
    if (query == null) return;
    await _run(query);
  }

  Future<void> goToPage(int index) async {
    final query = _query;
    if (query == null) return;
    final next = query.atPage(index);
    if (next.offset == query.offset) return;
    await _run(next);
  }

  /// Changing the order restarts the result set: an offset into the old
  /// ordering points at unrelated messages once the ordering changes.
  Future<void> setSort(MessageSearchSort value) async {
    if (_sort == value) return;
    _sort = value;
    final query = _query;
    if (query == null) {
      notifyListeners();
      return;
    }
    await _run(query.sortedBy(value));
  }

  /// Drops the results and abandons anything still in flight.
  void clear() {
    _cancelActive();
    _generation++;
    _scope = null;
    _query = null;
    _results = null;
    _indexing = null;
    _error = null;
    _text = '';
    _unresolved = const [];
    _status = MessageSearchStatus.idle;
    notifyListeners();
  }

  /// The channel a hit belongs to, named from the envelope when the workspace
  /// has never loaded it — a thread nobody opened still has to say where it is.
  String? channelNameFor(String channelId) {
    for (final channel in _results?.channels ?? const []) {
      if (channel.id == channelId) return channel.name;
    }
    return null;
  }

  Future<void> _run(MessageSearchQuery query) async {
    final scope = _scope;
    final repository = _repositoryProvider();
    if (scope == null || repository == null) return;
    final generation = ++_generation;
    _query = query;
    // Discord clears the previous page the moment a new request starts, so a
    // stale page is never shown under a spinner that belongs to another query.
    _results = null;
    _indexing = null;
    _error = null;
    _status = MessageSearchStatus.searching;
    notifyListeners();
    try {
      final outcome = await repository.searchMessages(
        MessageSearchRequest(scope: scope, query: query),
        onIndexing: (status) => _reportIndexing(generation, status),
      );
      if (generation != _generation || _disposed) return;
      switch (outcome) {
        case MessageSearchCompleted(:final results):
          _results = results;
          _indexing = null;
          _status = MessageSearchStatus.ready;
        case MessageSearchIndexing():
          // The retry budget ran out with the index still being built. The
          // honest answer is "not ready yet", never "no results".
          _indexing = outcome;
          _status = MessageSearchStatus.indexing;
        case MessageSearchCancelled():
          return;
      }
    } catch (error) {
      if (generation != _generation || _disposed) return;
      _error = error;
      _status = MessageSearchStatus.failed;
    }
    notifyListeners();
  }

  void _reportIndexing(int generation, MessageSearchIndexing status) {
    if (generation != _generation || _disposed) return;
    _indexing = status;
    _status = MessageSearchStatus.indexing;
    notifyListeners();
  }

  void _cancelActive() {
    final scope = _scope;
    if (scope == null) return;
    _repositoryProvider()?.cancelSearch(scope);
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelActive();
    super.dispose();
  }
}
