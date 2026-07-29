import 'dart:async';

import '../../domain/discord_relationship.dart';

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
