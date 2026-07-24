import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/discord_friends_controller.dart';
import '../../domain/discord_relationship.dart';
import '../../theme/flucord_theme.dart';
import 'discord_friend_actions.dart';
import 'discord_account_connection_scope.dart';
import 'discord_friends_scope.dart';
import 'discord_social_sdk_scope.dart';
import 'discord_social_dm_navigation_scope.dart';
import 'discord_social_dm_scope.dart';
import 'remote_identity_image.dart';

class DiscordFriendDirectory extends StatelessWidget {
  const DiscordFriendDirectory({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = DiscordFriendsScope.of(context);
    final socialController = DiscordSocialSdkScope.of(context);
    final accountController = DiscordAccountConnectionScope.maybeOf(context);
    final dmController = DiscordSocialDmScope.of(context);
    final dmNavigation = DiscordSocialDmNavigationScope.of(context);
    return switch (controller.state) {
      DiscordFriendsLoadState.idle ||
      DiscordFriendsLoadState.loading => const _FriendsState(
        key: ValueKey('discord-friends-loading'),
        loading: true,
        title: 'Loading friends',
        detail: 'Synchronizing native Discord relationships.',
      ),
      DiscordFriendsLoadState.authorizationRequired => _FriendsState(
        key: const ValueKey('discord-friends-auth-required'),
        icon: Icons.key_outlined,
        title: 'Native account authorization required',
        detail:
            'Connect your Discord account through the native Social SDK to synchronize friends.',
        action: FilledButton(
          key: const ValueKey('discord-friends-authorize'),
          onPressed: accountController?.connect ?? socialController.authorize,
          child: const Text('Connect Discord'),
        ),
      ),
      DiscordFriendsLoadState.unavailable => const _FriendsState(
        key: ValueKey('discord-friends-unavailable'),
        icon: Icons.extension_off_outlined,
        title: 'Friends are unavailable in this build',
        detail: 'The native Social SDK relationship transport is not active.',
      ),
      DiscordFriendsLoadState.failure => _FriendsState(
        key: const ValueKey('discord-friends-failure'),
        icon: Icons.error_outline,
        title: 'Friends could not be loaded',
        detail: 'The native relationship request failed without cached data.',
        action: OutlinedButton(
          onPressed: controller.retry,
          child: const Text('Retry'),
        ),
      ),
      DiscordFriendsLoadState.ready => _ReadyFriendDirectory(
        controller: controller,
        relationships: controller.relationships,
        onMessage: (user) {
          dmController.ensureConversation(user);
          dmNavigation.openConversation(user.id);
          unawaited(dmController.loadMessages(user.id));
        },
      ),
    };
  }
}

class _ReadyFriendDirectory extends StatelessWidget {
  const _ReadyFriendDirectory({
    required this.controller,
    required this.relationships,
    required this.onMessage,
  });

  final DiscordFriendsController controller;
  final List<DiscordRelationship> relationships;
  final ValueChanged<DiscordRelationshipUser> onMessage;

  @override
  Widget build(BuildContext context) {
    final items = _items(relationships);
    if (items.isEmpty) {
      return const _FriendsState(
        key: ValueKey('discord-friends-empty'),
        icon: Icons.people_outline,
        title: 'No friends to show',
        detail: 'Discord returned no friend or pending-request relationships.',
      );
    }
    return ListView.builder(
      key: const ValueKey('discord-friend-directory'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      itemCount: items.length,
      itemBuilder: (context, index) => switch (items[index]) {
        final _FriendSection section => Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
          child: Text(
            '${section.label.toUpperCase()} — ${section.count}',
            style: TextStyle(
              color: context.surfaces.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.25,
            ),
          ),
        ),
        final DiscordRelationship relationship => _FriendRow(
          controller: controller,
          relationship: relationship,
          onMessage: () => onMessage(relationship.user),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  static List<Object> _items(List<DiscordRelationship> relationships) {
    final pending = relationships.where((item) => item.isPending).toList();
    final online = relationships
        .where(
          (item) =>
              item.kind == DiscordRelationshipKind.friend &&
              item.user.status != DiscordPresenceStatus.offline &&
              item.user.status != DiscordPresenceStatus.unknown,
        )
        .toList();
    final offline = relationships
        .where(
          (item) =>
              item.kind == DiscordRelationshipKind.friend &&
              (item.user.status == DiscordPresenceStatus.offline ||
                  item.user.status == DiscordPresenceStatus.unknown),
        )
        .toList();
    final items = <Object>[];
    _appendGroup(items, 'Pending', pending);
    _appendGroup(items, 'Online', online);
    _appendGroup(items, 'Offline', offline);
    return items;
  }

  static void _appendGroup(
    List<Object> target,
    String label,
    List<DiscordRelationship> relationships,
  ) {
    if (relationships.isEmpty) return;
    target
      ..add(_FriendSection(label, relationships.length))
      ..addAll(relationships);
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.controller,
    required this.relationship,
    required this.onMessage,
  });

  final DiscordFriendsController controller;
  final DiscordRelationship relationship;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final user = relationship.user;
    final mutationFailed = controller.mutationErrorFor(user.id) != null;
    return Semantics(
      label: '${user.displayName}, ${_relationshipDetail(relationship)}',
      child: Container(
        key: ValueKey('discord-friend-${user.id}'),
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.surfaces.border)),
        ),
        child: Row(
          children: [
            _FriendAvatar(user: user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mutationFailed
                        ? 'Relationship action failed · Try again'
                        : _relationshipDetail(relationship),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mutationFailed
                          ? FlucordColors.danger
                          : context.surfaces.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            DiscordFriendActions(
              controller: controller,
              relationship: relationship,
              onMessage: onMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({required this.user});

  final DiscordRelationshipUser user;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        children: [
          ClipOval(
            child: RemoteIdentityImage(
              url: user.avatarUrl,
              fallback: ColoredBox(
                color: context.surfaces.raised,
                child: Center(
                  child: Text(
                    user.displayName.characters.first.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: _presenceColor(context, user.status),
                shape: BoxShape.circle,
                border: Border.all(color: context.surfaces.canvas, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendsState extends StatelessWidget {
  const _FriendsState({
    required this.title,
    required this.detail,
    this.icon,
    this.loading = false,
    this.action,
    super.key,
  });

  final String title;
  final String detail;
  final IconData? icon;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox.square(
                dimension: 26,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, size: 30, color: context.surfaces.muted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.surfaces.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            if (action case final action?) ...[
              const SizedBox(height: 14),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

final class _FriendSection {
  const _FriendSection(this.label, this.count);

  final String label;
  final int count;
}

String _relationshipDetail(DiscordRelationship relationship) {
  final user = relationship.user;
  final suffix = user.isProvisional ? ' · Provisional account' : '';
  return switch (relationship.kind) {
        DiscordRelationshipKind.incomingRequest =>
          relationship.isSpamRequest
              ? 'Incoming request · Flagged as spam'
              : 'Incoming friend request',
        DiscordRelationshipKind.outgoingRequest => 'Outgoing friend request',
        _ => switch (user.status) {
          DiscordPresenceStatus.online => 'Online',
          DiscordPresenceStatus.idle => 'Idle',
          DiscordPresenceStatus.doNotDisturb => 'Do Not Disturb',
          DiscordPresenceStatus.offline => 'Offline',
          DiscordPresenceStatus.unknown =>
            user.username ?? 'Status unavailable',
        },
      } +
      suffix;
}

Color _presenceColor(BuildContext context, DiscordPresenceStatus status) =>
    switch (status) {
      DiscordPresenceStatus.online => FlucordColors.success,
      DiscordPresenceStatus.idle => FlucordColors.warning,
      DiscordPresenceStatus.doNotDisturb => FlucordColors.danger,
      DiscordPresenceStatus.offline ||
      DiscordPresenceStatus.unknown => context.surfaces.muted,
    };
