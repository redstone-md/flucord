import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/discord_social_presence_controller.dart';
import '../../domain/discord_oauth.dart';
import '../../domain/discord_social_presence.dart';
import '../../theme/flucord_theme.dart';
import 'discord_social_presence_scope.dart';
import 'remote_identity_image.dart';

class OAuthAccountFooter extends StatelessWidget {
  const OAuthAccountFooter({required this.account, super.key});

  final DiscordOAuthAccount account;

  @override
  Widget build(BuildContext context) {
    final presence = DiscordSocialPresenceScope.maybeOf(context);
    final activePresence =
        presence == null ||
            presence.state == DiscordSocialPresenceState.unavailable
        ? null
        : presence;
    final hasNativePresence = activePresence != null;
    final visibleStatus =
        activePresence?.status ?? DiscordOnlineStatus.invisible;
    final content = Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        border: Border(top: BorderSide(color: context.surfaces.border)),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 34,
            child: Stack(
              children: [
                Positioned.fill(
                  right: 2,
                  bottom: 2,
                  child: ClipOval(
                    child: RemoteIdentityImage(
                      url: account.avatarUrl,
                      fallback: ColoredBox(
                        color: context.surfaces.raised,
                        child: const Icon(Icons.person_outline, size: 18),
                      ),
                    ),
                  ),
                ),
                if (hasNativePresence)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: _PresenceDot(status: visibleStatus),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  hasNativePresence
                      ? _statusLabel(visibleStatus)
                      : account.usernameLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        activePresence?.state ==
                            DiscordSocialPresenceState.failure
                        ? FlucordColors.danger
                        : context.surfaces.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            activePresence?.state == DiscordSocialPresenceState.updating
                ? Icons.sync
                : hasNativePresence
                ? Icons.keyboard_arrow_up
                : Icons.verified_user_outlined,
            size: 18,
            color: hasNativePresence
                ? context.surfaces.muted
                : FlucordColors.success,
          ),
        ],
      ),
    );
    if (activePresence == null) {
      return Tooltip(message: 'Linked Discord identity', child: content);
    }
    return Tooltip(
      message: activePresence.errorCode == null
          ? '${account.usernameLabel} · Change status'
          : 'Status update failed · Try again',
      child: PopupMenuButton<DiscordOnlineStatus>(
        key: const ValueKey('discord-online-status-menu'),
        enabled: activePresence.canUpdate,
        position: PopupMenuPosition.over,
        tooltip: '',
        onSelected: (status) => unawaited(activePresence.setStatus(status)),
        itemBuilder: (context) => [
          for (final status in DiscordOnlineStatus.values)
            PopupMenuItem(
              key: ValueKey('discord-online-status-${status.name}'),
              value: status,
              child: _StatusMenuItem(
                status: status,
                selected: activePresence.status == status,
              ),
            ),
        ],
        child: content,
      ),
    );
  }
}

class _StatusMenuItem extends StatelessWidget {
  const _StatusMenuItem({required this.status, required this.selected});

  final DiscordOnlineStatus status;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PresenceDot(status: status),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _statusLabel(status),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        if (selected)
          const Icon(Icons.check, size: 17, color: FlucordColors.brand),
      ],
    );
  }
}

class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.status});

  final DiscordOnlineStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: _statusColor(context, status),
        shape: BoxShape.circle,
        border: Border.all(color: context.surfaces.inset, width: 2),
      ),
    );
  }
}

String _statusLabel(DiscordOnlineStatus status) => switch (status) {
  DiscordOnlineStatus.online => 'Online',
  DiscordOnlineStatus.idle => 'Idle',
  DiscordOnlineStatus.doNotDisturb => 'Do Not Disturb',
  DiscordOnlineStatus.invisible => 'Invisible',
};

Color _statusColor(BuildContext context, DiscordOnlineStatus status) =>
    switch (status) {
      DiscordOnlineStatus.online => FlucordColors.success,
      DiscordOnlineStatus.idle => FlucordColors.warning,
      DiscordOnlineStatus.doNotDisturb => FlucordColors.danger,
      DiscordOnlineStatus.invisible => context.surfaces.muted,
    };
