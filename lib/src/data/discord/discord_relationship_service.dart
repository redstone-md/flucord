import 'dart:async';

import '../../domain/discord_relationship.dart';
import '../../domain/friend_suggestion.dart';

/// The account's friend graph, as the desktop-user session is told it.
///
/// Discord hands the whole graph over in `READY.relationships` and then keeps
/// it current with three dispatches. There is no route to re-read it, which is
/// why this is a store fed by the gateway rather than a repository with a load
/// method — the same shape the conversation summaries take.
final class DiscordRelationshipService {
  final StreamController<List<DiscordRelationship>> _updates =
      StreamController.broadcast();
  final Map<String, DiscordRelationship> _byUserId = {};
  final Map<String, FriendSuggestion> _suggestions = {};

  /// Everybody the account has a relationship with, in a stable order:
  /// requests that want an answer first, then friends, then the rest.
  List<DiscordRelationship> get relationships {
    final ordered = _byUserId.values.toList()
      ..sort((left, right) {
        final rank = _rank(left.kind).compareTo(_rank(right.kind));
        if (rank != 0) return rank;
        return left.user.displayName.toLowerCase().compareTo(
          right.user.displayName.toLowerCase(),
        );
      });
    return List.unmodifiable(ordered);
  }

  Stream<List<DiscordRelationship>> get updates => _updates.stream;

  /// People Discord thinks the account may know, most recently offered first
  /// as Discord orders them.
  List<FriendSuggestion> get suggestions =>
      List.unmodifiable(_suggestions.values);

  /// Replaces the held suggestions with what the route answered.
  void replaceSuggestions(Iterable<FriendSuggestion> next) {
    _suggestions
      ..clear()
      ..addEntries(next.map((entry) => MapEntry(entry.userId, entry)));
  }

  /// Drops one, which is what dismissing does locally.
  void forgetSuggestion(String userId) => _suggestions.remove(userId);

  /// Folds a dispatch in, returning whether anything changed.
  bool accept(String eventName, Map<String, Object?> data) {
    switch (eventName) {
      case 'READY':
        // A fresh session replaces the graph rather than merging into it: the
        // list Discord sends at login is the whole truth, and anything held
        // from a previous session may have been undone elsewhere since.
        final replacement = <String, DiscordRelationship>{};
        for (final raw in _list(data['relationships'])) {
          final relationship = readRelationship(raw, users: data['users']);
          if (relationship != null) {
            replacement[relationship.user.id] = relationship;
          }
        }
        _byUserId
          ..clear()
          ..addAll(replacement);
      case 'RELATIONSHIP_ADD' || 'RELATIONSHIP_UPDATE':
        final relationship = readRelationship(
          data['relationship'] ?? data,
          users: null,
        );
        if (relationship == null) return false;
        _byUserId[relationship.user.id] = relationship;
      case 'FRIEND_SUGGESTION_CREATE':
        final suggestion = readSuggestion(data['suggestion'] ?? data);
        if (suggestion == null) return false;
        // A suggestion Discord repeats is not a second suggestion.
        if (_suggestions.containsKey(suggestion.userId)) return false;
        _suggestions[suggestion.userId] = suggestion;
      case 'FRIEND_SUGGESTION_DELETE':
        final id = data['suggested_user_id'] ?? data['user_id'];
        if (id is! String || _suggestions.remove(id) == null) return false;
      case 'RELATIONSHIP_REMOVE':
        final payload = data['relationship'] ?? data;
        final id = payload is Map ? payload['id'] : null;
        if (id is! String || _byUserId.remove(id) == null) return false;
      default:
        return false;
    }
    if (!_updates.isClosed) _updates.add(relationships);
    return true;
  }

  Future<void> close() async {
    if (!_updates.isClosed) await _updates.close();
  }

  /// Maps one suggestion, or null when it names nobody.
  ///
  /// Discord sends contact names only when there are at least two, so that a
  /// single contact cannot be singled out; that rule is kept here rather than
  /// re-derived, and anything shorter is dropped.
  static FriendSuggestion? readSuggestion(Object? raw) {
    if (raw is! Map) return null;
    final payload = raw.cast<String, Object?>();
    final user = payload['suggested_user'];
    if (user is! Map) return null;
    final fields = user.cast<String, Object?>();
    final id = fields['id'];
    if (id is! String || id.isEmpty) return null;
    final global = _text(fields['global_name']);
    final contacts = [
      for (final name in _list(payload['contact_names']))
        if (name is String && name.isNotEmpty) name,
    ];
    return FriendSuggestion(
      userId: id,
      displayName: global.isNotEmpty ? global : _text(fields['username']),
      reason: _reason(payload['reasons']),
      mutualFriendCount: payload['mutual_friends_count'] is int
          ? payload['mutual_friends_count']! as int
          : 0,
      contactNames: contacts.length >= 2 ? contacts.sublist(0, 2) : const [],
    );
  }

  static String _reason(Object? reasons) {
    for (final raw in _list(reasons)) {
      if (raw is Map && raw['name'] is String) return raw['name']! as String;
    }
    return '';
  }

  /// Maps one relationship, or null when it names nobody.
  ///
  /// `READY` sends the user inline on each relationship on current builds and
  /// as a separate table on older ones, so both are read: a relationship whose
  /// user is only in the table would otherwise arrive as a row with no name.
  static DiscordRelationship? readRelationship(
    Object? raw, {
    required Object? users,
  }) {
    if (raw is! Map) return null;
    final payload = raw.cast<String, Object?>();
    final id = payload['id'];
    if (id is! String || id.isEmpty) return null;
    final user = payload['user'] is Map
        ? (payload['user']! as Map).cast<String, Object?>()
        : _userFromTable(users, id);
    final username = _text(user?['username']);
    final global = _text(user?['global_name']);
    final nickname = _text(payload['nickname']);
    return DiscordRelationship(
      user: DiscordRelationshipUser(
        id: id,
        // The nickname this account gave wins: it is the name whoever set it
        // will recognise. Then Discord's display name, then the username.
        displayName: nickname.isNotEmpty
            ? nickname
            : global.isNotEmpty
            ? global
            : username,
        username: username.isEmpty ? null : username,
      ),
      kind: _kind(payload['type']),
    );
  }

  static Map<String, Object?>? _userFromTable(Object? users, String id) {
    for (final raw in _list(users)) {
      if (raw is! Map) continue;
      if (raw['id'] == id) return raw.cast<String, Object?>();
    }
    return null;
  }

  /// Discord's own codes. Anything newer than this build reads as unknown
  /// rather than being guessed at, and an implicit relationship — somebody the
  /// account plays with rather than asked for — keeps its own kind.
  static DiscordRelationshipKind _kind(Object? type) => switch (type) {
    1 => DiscordRelationshipKind.friend,
    2 => DiscordRelationshipKind.blocked,
    3 => DiscordRelationshipKind.incomingRequest,
    4 => DiscordRelationshipKind.outgoingRequest,
    5 => DiscordRelationshipKind.implicit,
    _ => DiscordRelationshipKind.unknown,
  };

  static int _rank(DiscordRelationshipKind kind) => switch (kind) {
    DiscordRelationshipKind.incomingRequest => 0,
    DiscordRelationshipKind.outgoingRequest => 1,
    DiscordRelationshipKind.friend => 2,
    DiscordRelationshipKind.implicit => 3,
    DiscordRelationshipKind.blocked => 4,
    DiscordRelationshipKind.unknown => 5,
  };

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static String _text(Object? value) => value is String ? value : '';
}
