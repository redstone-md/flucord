import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/desktop_relationship_repository.dart';
import '../domain/discord_relationship.dart';
import '../domain/friend_suggestion.dart';

/// Drives the friends surface.
///
/// Holds no list of its own: the graph lives in the session that was told it,
/// and this rebinds to whichever repository the signed-in transport offers.
/// Two copies of a friend list is two places for it to be wrong.
final class FriendsController extends ChangeNotifier {
  FriendsController(this._repositoryProvider);

  final DesktopRelationshipRepository? Function() _repositoryProvider;

  DesktopRelationshipRepository? _repository;
  StreamSubscription<List<DiscordRelationship>>? _updates;
  bool _busy = false;
  bool _refused = false;
  Object? _error;
  bool _disposed = false;

  bool _panelOpen = false;

  /// Whether the friends surface is showing instead of the conversations.
  ///
  /// Kept here rather than in the sidebar because the sidebar is rebuilt
  /// whenever anything about the workspace changes, and a flag that resets on
  /// every incoming message is a flag nobody can keep switched on.
  bool get isPanelOpen => _panelOpen;

  void togglePanel() {
    _panelOpen = !_panelOpen;
    _notify();
  }

  bool get isAvailable => _bind() != null;
  bool get isBusy => _busy;
  Object? get error => _error;

  /// The last request Discord would not send. Somebody with friend requests
  /// off is a fact about them, not a failure here.
  bool get lastRequestRefused => _refused;

  List<DiscordRelationship> get all => _bind()?.relationships ?? const [];

  /// People Discord thinks the account may know.
  ///
  /// Anybody already in the graph is filtered out here rather than trusted to
  /// be absent: a suggestion that arrived before a friendship was made would
  /// otherwise sit there offering to introduce two people who already know
  /// each other.
  List<FriendSuggestion> get suggestions {
    final known = {for (final entry in all) entry.user.id};
    return [
      for (final entry
          in _bind()?.friendSuggestions ?? const <FriendSuggestion>[])
        if (!known.contains(entry.userId)) entry,
    ];
  }

  /// Reads the suggestions again. Unlike the graph, Discord serves a route.
  Future<void> loadSuggestions() async {
    final repository = _bind();
    if (repository == null || _busy) return;
    _busy = true;
    _notify();
    try {
      await repository.loadFriendSuggestions();
    } on Object catch (error) {
      _error = error;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Says no to a suggestion. There is no relationship to undo: dismissing is
  /// the whole of saying no.
  Future<bool> dismissSuggestion(FriendSuggestion suggestion) =>
      _run((repository) => repository.dismissSuggestion(suggestion.userId));

  List<DiscordRelationship> get requests => [
    for (final entry in all)
      if (entry.isPending) entry,
  ];

  List<DiscordRelationship> get friends => [
    for (final entry in all)
      if (entry.kind == DiscordRelationshipKind.friend) entry,
  ];

  List<DiscordRelationship> get blocked => [
    for (final entry in all)
      if (entry.kind == DiscordRelationshipKind.blocked) entry,
  ];

  /// Relationships the account never asked for: somebody it plays with, and
  /// anything of a kind this build has not heard of. Shown rather than
  /// dropped — a relationship that exists and appears nowhere is one nobody
  /// can act on.
  List<DiscordRelationship> get others => [
    for (final entry in all)
      if (entry.kind == DiscordRelationshipKind.implicit ||
          entry.kind == DiscordRelationshipKind.unknown)
        entry,
  ];

  /// Sends a friend request by username.
  Future<bool> addFriend(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return false;
    return _run((repository) => repository.addFriend(trimmed));
  }

  /// Accepts a request. The same call as asking: Discord does not
  /// distinguish a request to somebody who already asked.
  Future<bool> acceptRequest(DiscordRelationship entry) =>
      _run((repository) => repository.addFriend(entry.user.id));

  /// Removes, declines, cancels or unblocks — one route for all four.
  Future<bool> remove(DiscordRelationship entry) =>
      _run((repository) => repository.removeRelationship(entry.user.id));

  Future<bool> block(DiscordRelationship entry) =>
      _run((repository) => repository.blockUser(entry.user.id));

  Future<bool> _run(
    Future<bool> Function(DesktopRelationshipRepository) action,
  ) async {
    final repository = _bind();
    if (repository == null || _busy) return false;
    _busy = true;
    _refused = false;
    _error = null;
    _notify();
    try {
      final accepted = await action(repository);
      _refused = !accepted;
      return accepted;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Rebinds when the session changed, so a sign-out does not leave the last
  /// account's friends on screen.
  DesktopRelationshipRepository? _bind() {
    final repository = _repositoryProvider();
    if (identical(repository, _repository)) return _repository;
    _repository = repository;
    unawaited(_updates?.cancel());
    _updates = repository?.relationshipUpdates.listen((_) => _notify());
    return repository;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    super.dispose();
  }
}
