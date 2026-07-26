import '../../domain/guild_member_list.dart';

/// One entry inside a member-list op.
///
/// The Gateway sends either a group header or a member; the member payload is
/// the same shape as `GUILD_MEMBER_ADD`, and its optional `presence` is the
/// only place a lazy member list reports presence, so both are carried out of
/// the parser instead of being discarded with the row.
final class DiscordMemberListItem {
  const DiscordMemberListItem({required this.row, this.member, this.presence});

  final GuildMemberListRow row;
  final Map<String, Object?>? member;
  final Map<String, Object?>? presence;

  static DiscordMemberListItem? fromJson(Map<String, Object?> json) {
    final group = json['group'];
    if (group is Map) {
      final id = group['id'];
      if (id is! String) return null;
      return DiscordMemberListItem(
        row: GuildMemberListGroupRow(
          groupId: id,
          count: _count(group['count']),
        ),
      );
    }
    final member = json['member'];
    if (member is! Map) return null;
    final payload = member.cast<String, Object?>();
    final user = payload['user'];
    if (user is! Map) return null;
    final userId = user['id'];
    if (userId is! String) return null;
    final presence = payload['presence'];
    return DiscordMemberListItem(
      row: GuildMemberListMemberRow(userId),
      member: payload,
      presence: presence is Map ? presence.cast<String, Object?>() : null,
    );
  }

  static int _count(Object? value) =>
      value is num ? (value < 0 ? 0 : value.round()) : 0;
}

/// A mutation the Gateway applies to a member list's flat row space.
sealed class DiscordMemberListOp {
  const DiscordMemberListOp();

  /// Parses one op, returning `null` for shapes Flucord does not act on.
  ///
  /// Unknown op names are ignored rather than rejected: Discord's own store
  /// falls through its switch silently, and a strict client would break the
  /// whole list the first time a new op is introduced.
  static DiscordMemberListOp? fromJson(Map<String, Object?> json) {
    final name = json['op'];
    if (name is! String) return null;
    switch (name) {
      case 'SYNC':
        final range = _range(json['range']);
        final items = json['items'];
        if (range == null || items is! List) return null;
        return DiscordMemberListSync(
          start: range.$1,
          end: range.$2,
          items: items
              .whereType<Map>()
              .map(
                (item) => DiscordMemberListItem.fromJson(
                  item.cast<String, Object?>(),
                ),
              )
              .toList(growable: false),
        );
      case 'INVALIDATE':
        final range = _range(json['range']);
        if (range == null) return null;
        return DiscordMemberListInvalidate(start: range.$1, end: range.$2);
      case 'INSERT':
      case 'UPDATE':
        final index = json['index'];
        final item = json['item'];
        if (index is! int || index < 0 || item is! Map) return null;
        final parsed = DiscordMemberListItem.fromJson(
          item.cast<String, Object?>(),
        );
        if (parsed == null) return null;
        return name == 'INSERT'
            ? DiscordMemberListInsert(index: index, item: parsed)
            : DiscordMemberListReplace(index: index, item: parsed);
      case 'DELETE':
        final index = json['index'];
        if (index is! int || index < 0) return null;
        return DiscordMemberListDelete(index);
      default:
        return null;
    }
  }

  static (int, int)? _range(Object? value) {
    if (value is! List || value.length < 2) return null;
    final start = value[0];
    final end = value[1];
    if (start is! int || end is! int || start < 0 || end < start) return null;
    return (start, end);
  }
}

/// Writes `items[i]` at absolute row `start + i`.
final class DiscordMemberListSync extends DiscordMemberListOp {
  const DiscordMemberListSync({
    required this.start,
    required this.end,
    required this.items,
  });

  final int start;
  final int end;
  final List<DiscordMemberListItem?> items;
}

/// Drops cached rows in a range the server no longer vouches for.
final class DiscordMemberListInvalidate extends DiscordMemberListOp {
  const DiscordMemberListInvalidate({required this.start, required this.end});

  final int start;
  final int end;
}

/// Splices a row in, shifting everything after it down.
final class DiscordMemberListInsert extends DiscordMemberListOp {
  const DiscordMemberListInsert({required this.index, required this.item});

  final int index;
  final DiscordMemberListItem item;
}

/// Replaces a row in place.
final class DiscordMemberListReplace extends DiscordMemberListOp {
  const DiscordMemberListReplace({required this.index, required this.item});

  final int index;
  final DiscordMemberListItem item;
}

/// Splices a row out, shifting everything after it up.
final class DiscordMemberListDelete extends DiscordMemberListOp {
  const DiscordMemberListDelete(this.index);

  final int index;
}

/// A parsed `GUILD_MEMBER_LIST_UPDATE` dispatch.
final class DiscordMemberListUpdate {
  const DiscordMemberListUpdate({
    required this.guildId,
    required this.listId,
    required this.ops,
    required this.groups,
    required this.memberCount,
    required this.onlineCount,
  });

  final String guildId;
  final String listId;
  final List<DiscordMemberListOp> ops;
  final List<GuildMemberListGroup> groups;
  final int memberCount;
  final int onlineCount;

  /// Members carried by this update, in op order, ready for the member cache.
  Iterable<DiscordMemberListItem> get memberItems sync* {
    for (final op in ops) {
      switch (op) {
        case DiscordMemberListSync(:final items):
          for (final item in items) {
            if (item?.member != null) yield item!;
          }
        case DiscordMemberListInsert(:final item) ||
            DiscordMemberListReplace(:final item):
          if (item.member != null) yield item;
        case DiscordMemberListInvalidate():
        case DiscordMemberListDelete():
          break;
      }
    }
  }

  static DiscordMemberListUpdate? fromDispatch(Map<String, Object?> data) {
    final guildId = data['guild_id'];
    final listId = data['id'];
    if (guildId is! String || listId is! String) return null;
    final rawOps = data['ops'];
    final rawGroups = data['groups'];
    return DiscordMemberListUpdate(
      guildId: guildId,
      listId: listId,
      ops: rawOps is List
          ? rawOps
                .whereType<Map>()
                .map(
                  (op) =>
                      DiscordMemberListOp.fromJson(op.cast<String, Object?>()),
                )
                .nonNulls
                .toList(growable: false)
          : const [],
      groups: rawGroups is List
          ? _layout(rawGroups.whereType<Map>().toList(growable: false))
          : const [],
      memberCount: _count(data['member_count']),
      onlineCount: _count(data['online_count']),
    );
  }

  /// Assigns each group the row its header occupies.
  static List<GuildMemberListGroup> _layout(List<Map<Object?, Object?>> raw) {
    final groups = <GuildMemberListGroup>[];
    var offset = 0;
    for (final entry in raw) {
      final id = entry['id'];
      if (id is! String) continue;
      final count = DiscordMemberListItem._count(entry['count']);
      groups.add(GuildMemberListGroup(id: id, count: count, index: offset));
      offset += count + 1;
    }
    return List<GuildMemberListGroup>.unmodifiable(groups);
  }

  static int _count(Object? value) =>
      value is num ? (value < 0 ? 0 : value.round()) : 0;
}
