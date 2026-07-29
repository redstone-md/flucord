import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../theme/flucord_theme.dart';
import 'activity_views.dart';
import 'member_avatar.dart';
import 'streamer_mode_scope.dart';
import 'self_presence_scope.dart';
import 'self_status_menu.dart';

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
    final presence = SelfPresenceScope.maybeOf(context);
    final (status, color, tooltip) = _transportStatus(context);
    // The account's own row is composed locally, so the panel prefers what
    // this client is broadcasting over whatever the member table last cached.
    final self = presence?.isAvailable ?? false
        ? presence!.userPresence
        : member.presenceOrCoarse;
    final custom = self.customStatus;
    final identity = Row(
      children: [
        MemberAvatar(
          member: member.withPresence(self),
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
                // Blanked rather than truncated: the panel is in the corner of
                // every frame of a stream, and a name half shown is still a
                // name shown.
                StreamerModeScope.hidesPersonalInformation(context)
                    ? 'Hidden'
                    : member.displayName,
                key: const ValueKey('account-panel-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              if (custom != null)
                ActivitySummaryLine(
                  key: const ValueKey('account-custom-status'),
                  activity: custom,
                )
              else
                Text(
                  presence?.isAvailable ?? false
                      ? self.displayStatus.label
                      : status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: presence?.isAvailable ?? false
                        ? context.surfaces.muted
                        : color,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
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
          Expanded(
            child: presence == null || !presence.isAvailable
                ? identity
                : SelfStatusMenu(controller: presence, child: identity),
          ),
          Tooltip(
            message: tooltip,
            child: Icon(Icons.sensors, size: 17, color: color),
          ),
        ],
      ),
    );
  }

  (String, Color, String) _transportStatus(BuildContext context) =>
      switch (sessionMode) {
        SessionMode.disconnected => (
          'Disconnected',
          context.surfaces.muted,
          'No chat transport',
        ),
        SessionMode.demo => (
          'Demo workspace',
          Theme.of(context).colorScheme.primary,
          'Deterministic demo data',
        ),
        SessionMode.discord => switch (connectionStatus) {
          RepositoryConnectionStatus.connected => (
            'Discord online',
            FlucordColors.success,
            'Discord Gateway',
          ),
          RepositoryConnectionStatus.connecting => (
            'Connecting...',
            FlucordColors.warning,
            'Discord Gateway',
          ),
          RepositoryConnectionStatus.reconnecting => (
            'Reconnecting...',
            FlucordColors.warning,
            'Discord Gateway',
          ),
          RepositoryConnectionStatus.offline => (
            'Offline',
            context.surfaces.muted,
            'Discord Gateway',
          ),
        },
      };
}
