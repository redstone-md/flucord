import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/desktop_relationship_repository.dart';
import '../domain/discord_relationship.dart';
import '../domain/discord_remote_auth.dart';
import '../domain/friend_suggestion.dart';
import '../domain/relationship_request.dart';

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
  bool _loadingSuggestions = false;
  RelationshipRefused? _refusal;
  RelationshipRequest? _heldForCaptcha;
  DiscordRemoteAuthCaptchaChallenge? _captcha;
  Object? _error;
  bool _disposed = false;

  bool _panelOpen = false;

  /// Whether the Friends page is showing instead of a conversation.
  ///
  /// Kept here rather than in the sidebar because the sidebar is rebuilt
  /// whenever anything about the workspace changes, and a flag that resets on
  /// every incoming message is a flag nobody can keep switched on.
  bool get isPanelOpen => _panelOpen;

  /// Shows the Friends page. Pressing Friends while it shows keeps it.
  void openPanel() => _setPanelOpen(true);

  /// Leaves the Friends page, as opening a conversation does.
  void closePanel() => _setPanelOpen(false);

  void _setPanelOpen(bool open) {
    if (_panelOpen == open) return;
    _panelOpen = open;
    _notify();
  }

  bool get isAvailable => _bind() != null;
  bool get isBusy => _busy;
  Object? get error => _error;

  /// Why Discord refused the last request, or null when it did not.
  /// Somebody with friend requests off is a fact about them, not a failure
  /// here.
  RelationshipRefused? get refusal {
    _bind();
    return _refusal;
  }

  /// The captcha Discord wants solved before it takes the last request.
  DiscordRemoteAuthCaptchaChallenge? get captcha {
    _bind();
    return _captcha;
  }

  List<DiscordRelationship> get all => _bind()?.relationships ?? const [];

  /// The account's relationship with [userId], or null for none.
  DiscordRelationship? relationshipWith(String userId) =>
      all.where((entry) => entry.user.id == userId).firstOrNull;

  /// Whether a friend request to [userId] makes sense: not somebody already
  /// a friend, already asked, or blocked.
  bool canBefriend(String userId) =>
      isAvailable &&
      switch (relationshipWith(userId)?.kind) {
        DiscordRelationshipKind.friend ||
        DiscordRelationshipKind.outgoingRequest ||
        DiscordRelationshipKind.blocked => false,
        _ => true,
      };

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
  ///
  /// A read, so it does not wait for [isBusy] or hold it: the panel asks
  /// once when it opens, which can be while a request is on its way.
  Future<void> loadSuggestions() async {
    final repository = _bind();
    if (repository == null || _loadingSuggestions) return;
    _loadingSuggestions = true;
    try {
      await repository.loadFriendSuggestions();
    } on Object catch (error) {
      _error = error;
    } finally {
      _loadingSuggestions = false;
      _notify();
    }
  }

  /// Says no to a suggestion. There is no relationship to undo: dismissing is
  /// the whole of saying no.
  Future<bool> dismissSuggestion(FriendSuggestion suggestion) =>
      _send(DismissSuggestion(suggestion.userId));

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

  /// Sends a friend request to whoever has [username].
  Future<bool> addFriendByUsername(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return false;
    return _send(BefriendUsername(trimmed));
  }

  /// Sends a friend request to [userId], as a suggestion or a profile card
  /// offers it.
  Future<bool> befriend(String userId) => _send(BefriendUser(userId));

  /// Accepts a request. The same call as asking: Discord does not
  /// distinguish a request to somebody who already asked.
  Future<bool> acceptRequest(DiscordRelationship entry) =>
      befriend(entry.user.id);

  /// Removes, declines, cancels or unblocks: one route for all four.
  Future<bool> remove(DiscordRelationship entry) =>
      _send(RemoveRelationship(entry.user.id));

  Future<bool> block(DiscordRelationship entry) =>
      _send(BlockUser(entry.user.id));

  /// Sends the request held for [captcha] again, with the solved [key].
  Future<bool> solveCaptcha(String key) async {
    _bind();
    final request = _heldForCaptcha;
    final challenge = _captcha;
    if (request == null || challenge == null) return false;
    return _send(request, captcha: DiscordCaptchaAnswer(challenge, key));
  }

  /// Drops the request held for [captcha].
  void cancelCaptcha() {
    _heldForCaptcha = null;
    _captcha = null;
    _notify();
  }

  /// Sends [request] and records how Discord answered. Returns whether it
  /// was taken.
  Future<bool> _send(
    RelationshipRequest request, {
    DiscordCaptchaAnswer? captcha,
  }) async {
    final repository = _bind();
    if (repository == null || _busy) return false;
    _busy = true;
    _refusal = null;
    _heldForCaptcha = null;
    _captcha = null;
    _error = null;
    _notify();
    try {
      switch (await repository.send(request, captcha: captcha)) {
        case RelationshipDone():
          return true;
        case final RelationshipRefused refusal:
          _refusal = refusal;
        case RelationshipCaptchaRequired(:final challenge):
          _heldForCaptcha = request;
          _captcha = challenge;
      }
      return false;
    } on Object catch (error) {
      _error = error;
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Rebinds when the session changed, so a sign-out does not leave the last
  /// account's friends on screen. What the last account was asked or told
  /// goes with it: a captcha solved later must not send its request as the
  /// new account.
  DesktopRelationshipRepository? _bind() {
    final repository = _repositoryProvider();
    if (identical(repository, _repository)) return _repository;
    _repository = repository;
    _heldForCaptcha = null;
    _captcha = null;
    _refusal = null;
    _error = null;
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
