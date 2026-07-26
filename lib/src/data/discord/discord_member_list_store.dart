import '../../domain/guild_member_list.dart';
import 'discord_member_list_update.dart';

/// Applies `GUILD_MEMBER_LIST_UPDATE` ops to cached member lists.
///
/// Discord streams member lists as deltas against a flat row space the client
/// is expected to maintain, so the roster only stays correct if every op is
/// applied in order with the same semantics the server assumes. The store is
/// deliberately transport-shaped and holds no Flutter or repository state; the
/// controller above it decides what to render.
final class DiscordMemberListStore {
  final Map<String, GuildMemberList> _lists = {};

  /// Snapshot of every known list, keyed by `guildId:listId`.
  Map<String, GuildMemberList> get lists => Map.unmodifiable(_lists);

  GuildMemberList? listFor(String guildId, String listId) =>
      _lists['$guildId:$listId'];

  /// Applies one dispatch and returns the resulting list.
  GuildMemberList apply(DiscordMemberListUpdate update) {
    final key = '${update.guildId}:${update.listId}';
    final current =
        _lists[key] ??
        GuildMemberList.pending(guildId: update.guildId, listId: update.listId);

    final rows = List<GuildMemberListRow?>.of(current.rows);
    for (final op in update.ops) {
      _applyOp(rows, op);
    }
    _resize(rows, update.groups);

    final next = current.copyWith(
      rows: List<GuildMemberListRow?>.unmodifiable(rows),
      groups: update.groups,
      memberCount: update.memberCount,
      onlineCount: update.onlineCount,
      version: current.version + 1,
    );
    _lists[key] = next;
    return next;
  }

  /// Forgets every list for a guild, as Discord does on `GUILD_DELETE`.
  void clearGuild(String guildId) =>
      _lists.removeWhere((key, list) => list.guildId == guildId);

  /// Forgets everything, as Discord does on a fresh connection.
  void clear() => _lists.clear();

  static void _applyOp(List<GuildMemberListRow?> rows, DiscordMemberListOp op) {
    switch (op) {
      case DiscordMemberListSync(:final start, :final items):
        for (var offset = 0; offset < items.length; offset++) {
          final item = items[offset];
          if (item == null) continue;
          _write(rows, start + offset, item.row);
        }
      case DiscordMemberListInvalidate(:final start, :final end):
        for (var index = start; index <= end && index < rows.length; index++) {
          // The server only guarantees a contiguous cached prefix, so stopping
          // at the first hole prevents clearing rows a later range still owns.
          if (rows[index] == null) break;
          rows[index] = null;
        }
      case DiscordMemberListInsert(:final index, :final item):
        if (index >= maxRows) return;
        if (index > rows.length) {
          _write(rows, index, item.row);
        } else {
          rows.insert(index, item.row);
        }
      case DiscordMemberListReplace(:final index, :final item):
        _write(rows, index, item.row);
      case DiscordMemberListDelete(:final index):
        if (index < rows.length) rows.removeAt(index);
    }
  }

  /// Rows a single list may hold.
  ///
  /// Every index in an op comes from the server, and the row space is grown to
  /// reach it. Discord's own client subscribes at most a handful of hundred-row
  /// pages, so a list this long cannot arise from real use — but an index field
  /// is attacker-influenced input, and without a ceiling one op could ask for
  /// an arbitrary allocation.
  static const maxRows = 200000;

  static void _write(
    List<GuildMemberListRow?> rows,
    int index,
    GuildMemberListRow row,
  ) {
    if (index >= maxRows) return;
    while (rows.length <= index) {
      rows.add(null);
    }
    rows[index] = row;
  }

  /// Truncates or extends the row space to match the authoritative groups.
  static void _resize(
    List<GuildMemberListRow?> rows,
    List<GuildMemberListGroup> groups,
  ) {
    if (groups.isEmpty) return;
    final last = groups.last;
    final total = (last.index + last.count + 1).clamp(0, maxRows);
    if (rows.length > total) {
      rows.removeRange(total, rows.length);
      return;
    }
    while (rows.length < total) {
      rows.add(null);
    }
  }
}
