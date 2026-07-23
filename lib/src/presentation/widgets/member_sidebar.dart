import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';

class MemberSidebar extends StatelessWidget {
  const MemberSidebar({
    required this.members,
    required this.spaceId,
    super.key,
  });

  final List<Member> members;
  final String spaceId;

  @override
  Widget build(BuildContext context) {
    final visibleMembers = members
        .where(
          (member) =>
              member.spaceIds.isEmpty || member.spaceIds.contains(spaceId),
        )
        .toList(growable: false);
    final online = visibleMembers
        .where((member) => member.presence != Presence.offline)
        .toList(growable: false);
    final offline = visibleMembers
        .where((member) => member.presence == Presence.offline)
        .toList(growable: false);
    final roleGroups = <String, List<Member>>{};
    for (final member in online) {
      roleGroups.putIfAbsent(member.roleFor(spaceId), () => []).add(member);
    }
    return Container(
      width: 224,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(left: BorderSide(color: context.surfaces.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
        children: [
          for (final entry in roleGroups.entries) ...[
            _MemberGroupLabel(label: entry.key, count: entry.value.length),
            for (final member in entry.value)
              _MemberRow(
                member: member,
                role: member.roleFor(spaceId),
                spaceId: spaceId,
              ),
            const SizedBox(height: 14),
          ],
          if (offline.isNotEmpty) ...[
            _MemberGroupLabel(label: 'Offline', count: offline.length),
            for (final member in offline)
              _MemberRow(
                member: member,
                role: member.roleFor(spaceId),
                spaceId: spaceId,
              ),
          ],
        ],
      ),
    );
  }
}

class _MemberGroupLabel extends StatelessWidget {
  const _MemberGroupLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 7),
      child: Text(
        '$label - $count',
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.role,
    required this.spaceId,
  });

  final Member member;
  final String role;
  final String spaceId;

  @override
  Widget build(BuildContext context) {
    final offline = member.presence == Presence.offline;
    return Opacity(
      opacity: offline ? 0.58 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            MemberAvatar(member: member, size: 32, spaceId: spaceId),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    role,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
