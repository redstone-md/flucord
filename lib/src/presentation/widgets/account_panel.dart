import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';

class AccountPanel extends StatelessWidget {
  const AccountPanel({
    required this.member,
    required this.sessionMode,
    required this.connectionStatus,
    super.key,
  });

  final Member member;
  final SessionMode sessionMode;
  final RepositoryConnectionStatus connectionStatus;

  @override
  Widget build(BuildContext context) {
    final (status, color) = sessionMode == SessionMode.local
        ? ('Local workspace', FlucordColors.success)
        : switch (connectionStatus) {
            RepositoryConnectionStatus.connected => (
              'Discord online',
              FlucordColors.success,
            ),
            RepositoryConnectionStatus.connecting => (
              'Connecting...',
              FlucordColors.warning,
            ),
            RepositoryConnectionStatus.reconnecting => (
              'Reconnecting...',
              FlucordColors.warning,
            ),
            RepositoryConnectionStatus.offline => (
              'Offline',
              context.surfaces.muted,
            ),
          };
    return Container(
      key: const ValueKey('account-panel'),
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border(top: BorderSide(color: context.surfaces.border)),
      ),
      child: Row(
        children: [
          MemberAvatar(
            member: member,
            size: 32,
            presenceBorderColor: context.surfaces.inset,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 10),
                ),
              ],
            ),
          ),
          Tooltip(
            message: sessionMode == SessionMode.local
                ? 'Local workspace'
                : 'Discord Gateway',
            child: Icon(Icons.sensors, size: 17, color: color),
          ),
        ],
      ),
    );
  }
}
