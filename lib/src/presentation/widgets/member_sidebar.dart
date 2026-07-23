import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';

class MemberSidebar extends StatelessWidget {
  const MemberSidebar({required this.members, super.key});

  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final online = members
        .where((member) => member.presence != Presence.offline)
        .toList(growable: false);
    final offline = members
        .where((member) => member.presence == Presence.offline)
        .toList(growable: false);
    return Container(
      width: 224,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(left: BorderSide(color: context.surfaces.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
        children: [
          _MemberGroupLabel(label: 'Online', count: online.length),
          for (final member in online) _MemberRow(member: member),
          const SizedBox(height: 20),
          _MemberGroupLabel(label: 'Offline', count: offline.length),
          for (final member in offline) _MemberRow(member: member),
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
  const _MemberRow({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final offline = member.presence == Presence.offline;
    return Opacity(
      opacity: offline ? 0.58 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            MemberAvatar(member: member, size: 32),
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
                    member.role,
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
