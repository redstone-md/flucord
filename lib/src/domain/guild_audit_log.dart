part 'guild_audit_log_actions.dart';

/// One `{key, old_value, new_value}` triple.
final class AuditLogChange {
  const AuditLogChange({required this.key, this.oldValue, this.newValue});

  final String key;
  final Object? oldValue;
  final Object? newValue;
}

/// One raw entry of `audit_log_entries`.
final class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.action,
    required this.timestamp,
    this.targetId,
    this.userId,
    this.reason,
    this.changes = const [],
    this.options = const {},
  });

  final String id;
  final AuditLogActionType action;

  /// Derived from the snowflake. The API sends no timestamp field at all, so
  /// an entry whose id is opaque lands on Discord's epoch rather than aborting
  /// a page.
  final DateTime timestamp;

  final String? targetId;
  final String? userId;
  final String? reason;
  final List<AuditLogChange> changes;
  final Map<String, Object?> options;

  AuditLogTargetType get targetType => action.targetType;
  AuditLogActionClass get actionClass => action.actionClass;
}

/// Consecutive entries the log presents as one line.
final class AuditLogRecord {
  const AuditLogRecord({
    required this.entries,
    required this.timestampStart,
    required this.timestampEnd,
  });

  /// Never empty: a record exists because an entry created it.
  final List<AuditLogEntry> entries;
  final DateTime timestampStart;
  final DateTime timestampEnd;

  AuditLogEntry get head => entries.first;
  int get count => entries.length;
  bool get isMerged => entries.length > 1;

  /// Every change the merged entries carry, head first.
  List<AuditLogChange> get changes => [
    for (final entry in entries) ...entry.changes,
  ];
}

/// One page of `GET /guilds/{id}/audit-logs`.
final class AuditLogPage {
  const AuditLogPage({
    required this.entries,
    this.userNames = const {},
    this.channelNames = const {},
  });

  /// Newest first, exactly as the API returns them.
  final List<AuditLogEntry> entries;

  /// Display names for the `users` array the response ships alongside, so the
  /// log can name an actor who is no longer a member of the guild.
  final Map<String, String> userNames;

  /// Names for the `threads` array, same reason.
  final Map<String, String> channelNames;

  /// Whether an older page exists.
  ///
  /// A short page means the end of the log — the renderer's rule, and the only
  /// signal there is, since the response carries no cursor.
  bool get hasOlderEntries => entries.length >= AuditLogQuery.pageSize;

  /// The cursor for the next page.
  String? get oldestEntryId => entries.isEmpty ? null : entries.last.id;
}

/// The query parameters `GET /guilds/{id}/audit-logs` accepts.
final class AuditLogQuery {
  const AuditLogQuery({this.before, this.userId, this.action, this.targetId});

  /// Discord's own page size, and the number [AuditLogPage.hasOlderEntries]
  /// compares against.
  static const pageSize = 50;

  final String? before;
  final String? userId;

  /// `null` is the wire encoding of "all actions": the key is omitted.
  final AuditLogActionType? action;

  final String? targetId;

  AuditLogQuery pageAfter(String? cursor) => AuditLogQuery(
    before: cursor,
    userId: userId,
    action: action,
    targetId: targetId,
  );

  Map<String, Object?> toQueryParameters() => {
    'limit': pageSize,
    'before': before,
    'user_id': userId,
    'action_type': action?.wireValue,
    'target_id': targetId,
  };
}

/// Collapses a page of entries the way Discord's log reads them.
///
/// Without this the log is unreadable: renaming twelve channels in one sitting
/// produces twelve lines that say the same thing. Discord folds consecutive
/// entries into one when they share actor, target, action and options and fall
/// inside half an hour of each other.
///
/// The exclusions are not arbitrary. Message and member actions are excluded
/// because each one is about a *different* subject even when the target id
/// matches, invites because their target is the code and merging two hides the
/// second, and prune because the interesting part is the count on each run.
abstract final class AuditLogMerge {
  /// The window two entries must fall inside to merge.
  static const window = Duration(minutes: 30);

  /// The most entries one record may absorb.
  static const maxRunLength = 50;

  static const _excluded = {
    AuditLogActionType.messageDelete,
    AuditLogActionType.messageBulkDelete,
    AuditLogActionType.messagePin,
    AuditLogActionType.messageUnpin,
    AuditLogActionType.memberMove,
    AuditLogActionType.memberDisconnect,
    AuditLogActionType.botAdd,
    AuditLogActionType.applicationCommandPermissionUpdate,
    AuditLogActionType.memberPrune,
  };

  /// Merges [entries], which arrive newest first, and answers newest first.
  static List<AuditLogRecord> apply(List<AuditLogEntry> entries) {
    final records = <AuditLogRecord>[];
    // The renderer reverses the page to oldest-first before folding, so a run
    // grows forward in time and `timestampEnd` really is the later moment.
    for (final entry in entries.reversed) {
      final head = records.isEmpty ? null : records.last;
      if (head != null && _mergeable(head, entry)) {
        records[records.length - 1] = AuditLogRecord(
          entries: [...head.entries, entry],
          timestampStart: head.timestampStart,
          timestampEnd: entry.timestamp,
        );
        continue;
      }
      records.add(
        AuditLogRecord(
          entries: [entry],
          timestampStart: entry.timestamp,
          timestampEnd: entry.timestamp,
        ),
      );
    }
    return List.unmodifiable(records.reversed);
  }

  static bool _mergeable(AuditLogRecord record, AuditLogEntry entry) {
    final head = record.head;
    if (head.action != entry.action) return false;
    if (head.targetId != entry.targetId) return false;
    if (head.userId != entry.userId) return false;
    if (record.count >= maxRunLength) return false;
    if (head.targetType == AuditLogTargetType.invite) return false;
    if (_excluded.contains(entry.action)) return false;
    if (entry.timestamp.difference(record.timestampStart).abs() >= window) {
      return false;
    }
    return _sameOptions(head.options, entry.options);
  }

  static bool _sameOptions(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key)) return false;
      if (!_sameValue(entry.value, right[entry.key])) return false;
    }
    return true;
  }

  static bool _sameValue(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return _sameOptions(
        left.cast<String, Object?>(),
        right.cast<String, Object?>(),
      );
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_sameValue(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }
}
