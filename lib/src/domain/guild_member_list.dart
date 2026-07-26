/// One row of a guild member list.
///
/// Discord addresses member lists as a single flat row space in which a group
/// header occupies a row of its own, so `range`, `index`, and every op in a
/// `GUILD_MEMBER_LIST_UPDATE` count headers and members alike. Modelling both
/// as rows keeps those indices meaningful instead of forcing a translation
/// layer that would drift from the wire.
sealed class GuildMemberListRow {
  const GuildMemberListRow();
}

/// A group header, either a status bucket or a hoisted role.
final class GuildMemberListGroupRow extends GuildMemberListRow {
  const GuildMemberListGroupRow({required this.groupId, required this.count});

  /// `online`, `offline`, `unknown`, or a role snowflake.
  final String groupId;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is GuildMemberListGroupRow &&
      other.groupId == groupId &&
      other.count == count;

  @override
  int get hashCode => Object.hash(groupId, count);

  @override
  String toString() => 'GuildMemberListGroupRow($groupId, $count)';
}

/// A member row. The member itself lives in the member cache.
final class GuildMemberListMemberRow extends GuildMemberListRow {
  const GuildMemberListMemberRow(this.userId);

  final String userId;

  @override
  bool operator ==(Object other) =>
      other is GuildMemberListMemberRow && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;

  @override
  String toString() => 'GuildMemberListMemberRow($userId)';
}

/// A group header together with the row it starts at.
final class GuildMemberListGroup {
  const GuildMemberListGroup({
    required this.id,
    required this.count,
    required this.index,
  });

  final String id;
  final int count;

  /// Row occupied by this group's header.
  final int index;

  @override
  bool operator ==(Object other) =>
      other is GuildMemberListGroup &&
      other.id == id &&
      other.count == count &&
      other.index == index;

  @override
  int get hashCode => Object.hash(id, count, index);
}

/// A guild member list as the Gateway has described it so far.
///
/// [rows] is sparse: an entry is `null` for a row inside a range the client has
/// not subscribed to or that the server invalidated. Rendering must treat those
/// as placeholders rather than as absent members, because the counts in
/// [groups] still include them.
final class GuildMemberList {
  const GuildMemberList({
    required this.guildId,
    required this.listId,
    required this.rows,
    required this.groups,
    required this.memberCount,
    required this.onlineCount,
    required this.version,
  });

  /// A list the client knows about but has received no data for.
  factory GuildMemberList.pending({
    required String guildId,
    required String listId,
  }) => GuildMemberList(
    guildId: guildId,
    listId: listId,
    rows: const [],
    groups: const [
      GuildMemberListGroup(id: unknownGroupId, count: 0, index: 0),
    ],
    memberCount: 0,
    onlineCount: 0,
    version: 0,
  );

  static const onlineGroupId = 'online';
  static const offlineGroupId = 'offline';
  static const unknownGroupId = 'unknown';

  final String guildId;
  final String listId;
  final List<GuildMemberListRow?> rows;
  final List<GuildMemberListGroup> groups;
  final int memberCount;
  final int onlineCount;

  /// Bumped on every applied update so views can detect change cheaply.
  final int version;

  String get key => '$guildId:$listId';

  /// Whether the server has described this list yet.
  ///
  /// A freshly created list carries exactly one `unknown` group, which is the
  /// same signal Discord's own client uses to distinguish "empty" from
  /// "not loaded".
  bool get isLoaded => groups.length != 1 || groups.single.id != unknownGroupId;

  /// Members the `@everyone` mention would reach: every group's count.
  int get everyoneMentionSize =>
      groups.fold(0, (total, group) => total + group.count);

  /// Members the `@here` mention would reach: every group except `offline`.
  int get hereMentionSize => groups
      .where((group) => group.id != offlineGroupId)
      .fold(0, (total, group) => total + group.count);

  GuildMemberList copyWith({
    List<GuildMemberListRow?>? rows,
    List<GuildMemberListGroup>? groups,
    int? memberCount,
    int? onlineCount,
    int? version,
  }) => GuildMemberList(
    guildId: guildId,
    listId: listId,
    rows: rows ?? this.rows,
    groups: groups ?? this.groups,
    memberCount: memberCount ?? this.memberCount,
    onlineCount: onlineCount ?? this.onlineCount,
    version: version ?? this.version,
  );

  @override
  String toString() =>
      'GuildMemberList($key, rows: ${rows.length}, '
      'members: $memberCount, online: $onlineCount, v$version)';
}
