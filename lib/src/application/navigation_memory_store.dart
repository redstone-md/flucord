import 'dart:async';

import '../app_log.dart';
import '../domain/navigation_memory.dart';

/// What the app remembers about where the signed-in account was.
///
/// Changes apply here at once and reach the disk shortly after, in one write.
/// With no account open, as in a demo, the memory lasts until the app closes.
/// A write that fails costs the reader nothing but the memory, so it is logged.
final class NavigationMemoryStore implements ReadingPositions {
  NavigationMemoryStore([this._repository]);

  /// The most positions kept. A reader returns to few channels, and the whole
  /// file is written on each save.
  static const positionLimit = 100;

  static const _saveDelay = Duration(milliseconds: 500);

  final NavigationMemoryRepository? _repository;

  String? _accountId;
  String? _lastSpaceId;
  Map<String, String> _lastChannels = {};
  Set<String> _collapsedCategoryIds = {};
  Map<String, ReadingPosition> _positions = {};
  int _generation = 0;
  Timer? _pendingSave;
  Future<void> _lastWrite = Future.value();

  /// Changes each time the memory is replaced by another account's, or emptied.
  /// A selection made under an older generation does not carry over.
  int get generation => _generation;

  String? get lastSpaceId => _lastSpaceId;
  Set<String> get collapsedCategoryIds => _collapsedCategoryIds;

  String? lastChannelOf(String spaceId) => _lastChannels[spaceId];

  /// Replaces the memory with what [accountId] saved. The same account again,
  /// as on a retry, keeps what is here. An account that cannot be named has
  /// nothing saved and saves nothing.
  Future<void> openAccount(String? accountId) async {
    if (accountId == _accountId) return;
    _writePending();
    await _lastWrite;
    final saved = accountId == null ? null : await _load();
    _replaceWith(accountId, saved?.accountId == accountId ? saved : null);
  }

  /// Empties the memory, here and on disk. The disk is emptied with no account
  /// open too, because a sign-out can come from a launch that never connected.
  Future<void> forget() async {
    _pendingSave?.cancel();
    _pendingSave = null;
    _replaceWith(null, null);
    _enqueueWrite((repository) => repository.clear());
    await _lastWrite;
  }

  /// Notes the space open now and, when it has one worth landing on again, its
  /// channel.
  void rememberLocation(String spaceId, String? channelId) {
    _lastSpaceId = spaceId;
    if (channelId != null) _lastChannels[spaceId] = channelId;
    _scheduleSave();
  }

  void toggleCategory(String categoryId) {
    if (!_collapsedCategoryIds.add(categoryId)) {
      _collapsedCategoryIds.remove(categoryId);
    }
    _scheduleSave();
  }

  @override
  ReadingPosition? of(String channelId) => _positions[channelId];

  @override
  void keep(String channelId, ReadingPosition? position) {
    if (position == null) {
      if (_positions.remove(channelId) != null) _scheduleSave();
      return;
    }
    // Added again, so the map's order runs from least to most recently read.
    _positions.remove(channelId);
    _positions[channelId] = position;
    if (_positions.length > positionLimit) {
      _positions.remove(_positions.keys.first);
    }
    _scheduleSave();
  }

  /// Writes what is still waiting, for a process about to end.
  Future<void> flush() {
    _writePending();
    return _lastWrite;
  }

  /// Writes what is still waiting. The widgets are going, so nobody awaits it.
  void dispose() => _writePending();

  Future<NavigationMemory?> _load() async {
    try {
      return await _repository?.load();
    } on Object catch (error) {
      AppLog.warning(
        'navigation',
        'Navigation memory could not be read',
        error: error,
      );
      return null;
    }
  }

  void _replaceWith(String? accountId, NavigationMemory? saved) {
    _accountId = accountId;
    _lastSpaceId = saved?.lastSpaceId;
    _lastChannels = {...?saved?.lastChannels};
    _collapsedCategoryIds = {...?saved?.collapsedCategoryIds};
    _positions = {...?saved?.positions};
    _generation++;
  }

  void _scheduleSave() {
    if (_accountId == null || _repository == null) return;
    _pendingSave?.cancel();
    _pendingSave = Timer(_saveDelay, _writePending);
  }

  void _writePending() {
    if (_pendingSave == null) return;
    _pendingSave?.cancel();
    _pendingSave = null;
    final memory = NavigationMemory(
      accountId: _accountId!,
      lastSpaceId: _lastSpaceId,
      lastChannels: {..._lastChannels},
      collapsedCategoryIds: {..._collapsedCategoryIds},
      positions: {..._positions},
    );
    _enqueueWrite((repository) => repository.save(memory));
  }

  /// One write at a time, so an older one cannot finish last.
  void _enqueueWrite(Future<void> Function(NavigationMemoryRepository) write) {
    final repository = _repository;
    if (repository == null) return;
    _lastWrite = _lastWrite.then((_) async {
      try {
        await write(repository);
      } on Object catch (error) {
        AppLog.warning(
          'navigation',
          'Navigation memory could not be saved',
          error: error,
        );
      }
    });
  }
}
