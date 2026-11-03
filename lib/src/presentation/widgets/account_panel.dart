import 'package:flutter/material.dart';

import '../../application/connection_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
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
    final (status, color, tooltip) = _connectionLabels(context);
    // The account's own row is composed locally, so the panel prefers what
    // this client is broadcasting over whatever the member table last cached.
    final self = presence?.isAvailable ?? false
        ? presence!.userPresence
        : member.presenceOrCoarse;
    final custom = ActivitySummary.of([?self.customStatus]);
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
                  fontSize: FlucordType.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              if (custom != null)
                ActivitySummaryLine(
                  key: const ValueKey('account-custom-status'),
                  summary: custom,
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
                    fontSize: FlucordType.caption,
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

  (String, Color, String) _connectionLabels(BuildContext context) =>
      switch (sessionMode) {
        SessionMode.disconnected => (
          'Disconnected',
          context.surfaces.muted,
          'Not connected to Discord',
        ),
        SessionMode.demo => (
          'Demo workspace',
          Theme.of(context).colorScheme.primary,
          'Sample data, not your account',
        ),
        SessionMode.discord => switch (connectionStatus) {
          RepositoryConnectionStatus.connected => (
            'Discord online',
            context.surfaces.success,
            'Connected to Discord',
          ),
          RepositoryConnectionStatus.connecting => (
            'Connecting...',
            context.surfaces.warning,
            'Connecting to Discord',
          ),
          RepositoryConnectionStatus.reconnecting => (
            'Reconnecting...',
            context.surfaces.warning,
            'Reconnecting to Discord',
          ),
          RepositoryConnectionStatus.offline => (
            'Offline',
            context.surfaces.muted,
            'Not connected to Discord',
          ),
        },
      };
}
