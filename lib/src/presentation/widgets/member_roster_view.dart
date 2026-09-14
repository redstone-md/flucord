import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/guild_member_list.dart';
import '../../theme/flucord_theme.dart';

/// Reports the panel's scroll position in the units the range maths needs.
typedef MemberRosterViewportReport =
    void Function({
      required double scrollOffset,
      required double viewportHeight,
      required double rowHeight,
    });

/// Renders a guild member list exactly as the server laid it out.
///
/// Discord addresses rosters as one flat row space in which a group header
/// occupies a row, so this view never regroups anything: it walks the rows in
/// order and asks what each index is. That is also why a missing row renders a
/// placeholder rather than collapsing — the group counts above it still include
/// that row, and collapsing would shift every index the server is about to
/// address.
class MemberRosterView extends StatefulWidget {
  const MemberRosterView({
    required this.list,
    required this.memberOf,
    required this.roleNames,
    required this.memberRowBuilder,
    required this.onViewportChanged,
    super.key,
  });

  /// Fixed per-row extent. The range arithmetic converts pixels straight into
  /// row indices, which only holds while every row is the same height, so a
  /// header and a member row deliberately share one extent.
  static const rowHeight = 48.0;

  final GuildMemberList list;
  final Member? Function(String userId) memberOf;

  /// Role names by role id, for group headers that name a hoisted role.
  final Map<String, String> roleNames;
  final Widget Function(Member member) memberRowBuilder;
  final MemberRosterViewportReport onViewportChanged;

  @override
  State<MemberRosterView> createState() => _MemberRosterViewState();
}

class _MemberRosterViewState extends State<MemberRosterView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.list.rows;
    final headers = <int, GuildMemberListGroup>{
      for (final group in widget.list.groups) group.index: group,
    };
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => _report(notification.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => _report(notification.metrics),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          itemExtent: MemberRosterView.rowHeight,
          itemCount: rows.length,
          itemBuilder: (context, index) => _rowAt(rows, headers, index),
        ),
      ),
    );
  }

  Widget _rowAt(
    List<GuildMemberListRow?> rows,
    Map<int, GuildMemberListGroup> headers,
    int index,
  ) {
    // The groups table is re-sent whole with every update, so it describes a
    // header even for rows the client has never been sent.
    final header = headers[index];
    if (header != null) {
      return MemberGroupLabel(label: _titleFor(header.id), count: header.count);
    }
    return switch (rows[index]) {
      GuildMemberListGroupRow(:final groupId, :final count) => MemberGroupLabel(
        label: _titleFor(groupId),
        count: count,
      ),
      GuildMemberListMemberRow(:final userId) => switch (widget.memberOf(
        userId,
      )) {
        final Member member => widget.memberRowBuilder(member),
        _ => MemberRosterPlaceholderRow(index: index),
      },
      null => MemberRosterPlaceholderRow(index: index),
    };
  }

  /// Group ids are either a status bucket or a role id.
  ///
  /// An unresolvable role renders without a title, matching Discord: the count
  /// is still accurate and inventing a name would be worse than an empty one.
  String _titleFor(String groupId) => switch (groupId) {
    GuildMemberList.onlineGroupId => 'Online',
    GuildMemberList.offlineGroupId => 'Offline',
    GuildMemberList.unknownGroupId => 'Unknown',
    _ => widget.roleNames[groupId] ?? '',
  };

  bool _report(ScrollMetrics metrics) {
    if (metrics.hasViewportDimension && metrics.hasPixels) {
      widget.onViewportChanged(
        scrollOffset: metrics.pixels,
        viewportHeight: metrics.viewportDimension,
        rowHeight: MemberRosterView.rowHeight,
      );
    }
    return false;
  }
}

/// A group header row: the group's name and how many members it holds.
class MemberGroupLabel extends StatelessWidget {
  const MemberGroupLabel({required this.label, required this.count, super.key});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 7),
        child: Text(
          '$label - $count',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.surfaces.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A row inside a subscribed range the server has not answered for yet.
///
/// It has to occupy the row: the group counts already include it, so removing
/// it would renumber every row the next op addresses.
class MemberRosterPlaceholderRow extends StatelessWidget {
  const MemberRosterPlaceholderRow({required this.index, super.key});

  final int index;

  @override
  Widget build(BuildContext context) {
    final color = context.surfaces.raised;
    return Semantics(
      label: 'Loading member',
      child: Padding(
        key: ValueKey('member-row-placeholder-$index'),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
