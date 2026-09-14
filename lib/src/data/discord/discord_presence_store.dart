import '../../domain/chat_models.dart';
import 'discord_presence_mapper.dart';

part 'discord_presence_activities.dart';

/// The per-user × per-guild presence map, collapsed on read.
///
/// Discord reports the same user once per subscribed guild and once for the
/// friend list, and those copies disagree: a guild the client subscribed to
/// minutes ago answers with a stale frame long after the friend-scope one has
/// moved on. Keeping every scope and collapsing by `processed_at_timestamp` is
/// what makes the newest answer win; a flat "last frame received wins" map
/// silently shows whichever guild happened to speak last.
final class DiscordPresenceStore {
  /// The scope key for a presence that named no guild.
  ///
  /// R07 could not isolate the literal Discord uses, so this is treated as an
  /// opaque sentinel. It is prefixed with a character no snowflake contains,
  /// which is what keeps it from ever colliding with a real guild id.
  static const friendScope = '@me';

  final Map<String, Map<String, _PresenceCell>> _cells = {};
  String? _currentUserId;

  /// The account this client is signed in as.
  ///
  /// R07: the current user's own presence never travels through this map. It
  /// is composed locally, and letting a server echo overwrite it would make
  /// the account's own row flicker between what it chose and what the last
  /// guild frame happened to say.
  set currentUserId(String? value) {
    _currentUserId = value;
    if (value != null) _cells.remove(value);
  }

  /// The collapsed presence for a user, or null when none is known.
  UserPresence? presenceFor(String userId) => _collapse(userId);

  /// Every user the store currently holds a presence for.
  Map<String, UserPresence> get all => {
    for (final userId in _cells.keys.toList(growable: false))
      userId: ?_collapse(userId),
  };

  /// Folds a batch of presences in and reports the users whose answer changed.
  ///
  /// A user dropped from the map is reported as [UserPresence.offline] rather
  /// than omitted, because the caller has to clear the row it already drew.
  Map<String, UserPresence> apply(Iterable<DiscordPresenceRecord> records) {
    final touched = <String>{};
    for (final record in records) {
      if (_store(record)) touched.add(record.userId);
    }
    return _resolve(touched);
  }

  /// `PRESENCES_REPLACE`: the friend scope is reset wholesale, then refilled.
  ///
  /// Clearing first is what makes a friend who went offline while the client
  /// was away actually disappear — the replacement list simply omits them.
  Map<String, UserPresence> replaceFriendScope(
    Iterable<DiscordPresenceRecord> records,
  ) {
    final touched = <String>{};
    for (final entry in _cells.entries) {
      if (entry.value.remove(friendScope) != null) touched.add(entry.key);
    }
    for (final record in records) {
      if (_store(record, scope: friendScope)) touched.add(record.userId);
    }
    return _resolve(touched);
  }

  /// `GUILD_DELETE`: drops that guild's column for every user.
  Map<String, UserPresence> removeGuild(String guildId) {
    final touched = <String>{};
    for (final entry in _cells.entries) {
      if (entry.value.remove(guildId) != null) touched.add(entry.key);
    }
    return _resolve(touched);
  }

  /// `GUILD_MEMBER_REMOVE`: drops one cell.
  Map<String, UserPresence> removeMember({
    required String guildId,
    required String userId,
  }) {
    final scopes = _cells[userId];
    if (scopes == null || scopes.remove(guildId) == null) return const {};
    return _resolve({userId});
  }

  void clear() => _cells.clear();

  /// Writes one cell. Returns whether anything was stored or pruned.
  bool _store(DiscordPresenceRecord record, {String? scope}) {
    if (record.userId == _currentUserId) return false;
    final key = scope ?? record.guildId ?? friendScope;
    final presence = record.presence;
    final scopes = _cells[record.userId];
    // R07's offline pruning: an offline presence with nothing hidden is not
    // worth a row. For a user the store has never seen it is dropped outright,
    // which is what keeps a large guild's offline half out of memory.
    if (presence.status == Presence.offline &&
        presence.hiddenActivities.isEmpty) {
      if (scopes == null) return false;
      scopes[key] = _PresenceCell(
        status: presence.status,
        clientStatus: presence.clientStatus,
        processedAt: record.processedAtTimestamp,
      );
      return true;
    }
    (_cells[record.userId] ??= {})[key] = _PresenceCell(
      status: presence.status,
      clientStatus: presence.clientStatus,
      activities: DiscordPresenceActivities.sorted(presence.activities),
      hiddenActivities: DiscordPresenceActivities.dedupeHidden(
        presence.hiddenActivities,
      ),
      processedAt: record.processedAtTimestamp,
    );
    return true;
  }

  Map<String, UserPresence> _resolve(Set<String> userIds) => {
    for (final userId in userIds)
      userId: _collapse(userId) ?? UserPresence.offline,
  };

  /// R07's cross-guild collapse: newest `processed_at_timestamp` wins, ties
  /// break toward the entry carrying more activities.
  UserPresence? _collapse(String userId) {
    final scopes = _cells[userId];
    if (scopes == null || scopes.isEmpty) return null;
    _PresenceCell? best;
    var meaningful = false;
    for (final cell in scopes.values) {
      if (cell.isMeaningful) meaningful = true;
      if (best == null ||
          cell.processedAt > best.processedAt ||
          (cell.processedAt == best.processedAt &&
              cell.activities.length > best.activities.length)) {
        best = cell;
      }
    }
    // Every scope says offline with nothing hidden: the user is gone rather
    // than quietly present, so the whole row is dropped.
    if (!meaningful) {
      _cells.remove(userId);
      return null;
    }
    final hidden = DiscordPresenceActivities.dedupeHidden([
      for (final cell in scopes.values) ...cell.hiddenActivities,
    ]);
    return UserPresence(
      status: best!.status,
      clientStatus: best.clientStatus,
      activities: DiscordPresenceActivities.filterDuplicatePlaying(
        best.activities,
      ),
      hiddenActivities: hidden,
    );
  }
}

/// One `(user, scope)` cell of the presence map.
final class _PresenceCell {
  const _PresenceCell({
    required this.status,
    required this.clientStatus,
    required this.processedAt,
    this.activities = const [],
    this.hiddenActivities = const [],
  });

  final Presence status;
  final Map<ClientPlatform, Presence> clientStatus;
  final List<UserActivity> activities;
  final List<UserActivity> hiddenActivities;
  final int processedAt;

  /// Whether this cell is worth keeping the user in the map for.
  bool get isMeaningful =>
      status != Presence.offline || hiddenActivities.isNotEmpty;
}
