/// The `READY.users` table every compressed reference in the payload resolves
/// against.
///
/// READY never repeats a user object: DM recipients arrive as `recipient_ids`,
/// and guild members and presences arrive as `user_id`. Any section that
/// references a user is therefore unusable until it has been resolved here,
/// which is why the table is a session-scoped object shared by the DM directory
/// today and by the member-list phase later rather than a per-section detail.
///
/// Discord keeps the table alive from READY until READY_SUPPLEMENTAL has been
/// hydrated and then drops it. Holding it longer would let a user captured at
/// connect time shadow a later gateway update, so [clear] is part of the
/// contract, not housekeeping.
final class DiscordReadyUserTable {
  final Map<String, Map<String, Object?>> _users = {};
  final Set<String> _unresolvedIds = {};

  /// Ids a payload referenced that `READY.users` never carried.
  ///
  /// Discord asserts on the first one ("Missing user in compressed ready
  /// payload") and, with assertions compiled out, leaves a hole in the array it
  /// was expanding. Dropping the reference instead keeps the rest of the record
  /// usable, and recording it gives the caller something to report.
  Set<String> get unresolvedIds => Set.unmodifiable(_unresolvedIds);

  /// Indexes `READY.users`, ignoring entries without a usable id.
  void addAll(Object? users) {
    if (users is! List) return;
    for (final user in users.whereType<Map>()) {
      final id = user['id'];
      if (id is! String || id.isEmpty) continue;
      _users[id] = user.cast<String, Object?>();
    }
  }

  /// The user behind a bare id, or null when the table never carried it.
  Map<String, Object?>? user(String id) => _users[id];

  /// Resolves a list of bare ids, recording the ones that are absent.
  List<Map<String, Object?>> expandUserIds(Object? ids) {
    if (ids is! List) return const [];
    final resolved = <Map<String, Object?>>[];
    for (final id in ids.whereType<String>()) {
      final entry = user(id);
      if (entry == null) {
        _unresolvedIds.add(id);
        continue;
      }
      resolved.add(entry);
    }
    return resolved;
  }

  /// Rewrites a private channel's `recipient_ids` into full `recipients`.
  ///
  /// READY sends one form or the other, and the compressed field is removed
  /// once it has been expanded so nothing downstream has to know which form
  /// arrived.
  Map<String, Object?> expandRecipients(Map<String, Object?> channel) {
    final ids = channel['recipient_ids'];
    if (ids is! List) return channel;
    return Map<String, Object?>.of(channel)
      ..remove('recipient_ids')
      ..['recipients'] = expandUserIds(ids);
  }

  /// Rewrites a guild member's `user_id` into the full `user` object.
  ///
  /// Guild members arrive in `merged_members` compressed the same way DM
  /// recipients are, so a member is unusable — it has no name, no avatar, not
  /// even an id a roster row could key on — until this has run. A member whose
  /// user the table never carried is returned unchanged and recorded, so the
  /// caller can drop it rather than render a blank row.
  Map<String, Object?> expandMember(Map<String, Object?> member) {
    final id = member['user_id'];
    if (id is! String) return member;
    final entry = user(id);
    if (entry == null) {
      _unresolvedIds.add(id);
      return member;
    }
    return Map<String, Object?>.of(member)
      ..remove('user_id')
      ..['user'] = entry;
  }

  /// Drops the table, as Discord does once READY_SUPPLEMENTAL is applied.
  void clear() {
    _users.clear();
    _unresolvedIds.clear();
  }
}
