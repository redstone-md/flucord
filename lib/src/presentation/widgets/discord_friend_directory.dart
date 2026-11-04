import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/discord_friends_controller.dart';
import '../../domain/discord_relationship.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'discord_friend_actions.dart';
import 'discord_account_connection_scope.dart';
import 'discord_friends_scope.dart';
import 'discord_relationship_avatar.dart';
import 'discord_social_sdk_scope.dart';
import 'discord_social_dm_navigation_scope.dart';
import 'discord_social_dm_scope.dart';
import 'flucord_button.dart';
import 'profile_card.dart';
import 'popup_anchor.dart';
import 'profile_card_data.dart';
import 'profile_card_route.dart';

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
        icon: FlucordIcons.credential,
        title: 'Native account authorization required',
        detail:
            'Connect your Discord account through the native Social SDK to synchronize friends.',
        action: FlucordButton(
          key: const ValueKey('discord-friends-authorize'),
          kind: FlucordButtonKind.primary,
          label: 'Connect Discord',
          onPressed: accountController?.connect ?? socialController.authorize,
        ),
      ),
      DiscordFriendsLoadState.unavailable => const _FriendsState(
        key: ValueKey('discord-friends-unavailable'),
        icon: FlucordIcons.plugin,
        title: 'Friends are unavailable in this build',
        detail: 'The native Social SDK relationship transport is not active.',
      ),
      DiscordFriendsLoadState.failure => _FriendsState(
        key: const ValueKey('discord-friends-failure'),
        icon: FlucordIcons.error,
        title: 'Friends could not be loaded',
        detail: 'The native relationship request failed without cached data.',
        action: FlucordButton(label: 'Retry', onPressed: controller.retry),
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

class _ReadyFriendDirectory extends StatefulWidget {
  const _ReadyFriendDirectory({
    required this.controller,
    required this.relationships,
    required this.onMessage,
  });

  final DiscordFriendsController controller;
  final List<DiscordRelationship> relationships;
  final ValueChanged<DiscordRelationshipUser> onMessage;

  @override
  State<_ReadyFriendDirectory> createState() => _ReadyFriendDirectoryState();
}

class _ReadyFriendDirectoryState extends State<_ReadyFriendDirectory> {
  /// Whose card is open, and what closes it.
  String? _openUserId;
  VoidCallback? _closeCard;

  @override
  void didUpdateWidget(covariant _ReadyFriendDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    final openId = _openUserId;
    final close = _closeCard;
    if (openId != null &&
        close != null &&
        !widget.relationships.any((item) => item.user.id == openId)) {
      // Not during the build: closing pops a route.
      WidgetsBinding.instance.addPostFrameCallback((_) => close());
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(widget.relationships);
    if (items.isEmpty) {
      return const _FriendsState(
        key: ValueKey('discord-friends-empty'),
        icon: FlucordIcons.friends,
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
            '${section.label} ${section.count}',
            style: FlucordTextRole.caption.style.copyWith(
              color: context.surfaces.captionText,
            ),
          ),
        ),
        final DiscordRelationship relationship => _FriendRow(
          controller: widget.controller,
          relationship: relationship,
          selected: relationship.user.id == _openUserId,
          onProfile: (context) =>
              unawaited(_showProfile(context, relationship)),
          onMessage: () => widget.onMessage(relationship.user),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  /// Opens [relationship]'s card beside the row at [rowContext].
  Future<void> _showProfile(
    BuildContext rowContext,
    DiscordRelationship relationship,
  ) async {
    setState(() => _openUserId = relationship.user.id);
    await showProfileCard(
      context: rowContext,
      anchor: popupAnchorOf(rowContext),
      builder: (close) {
        _closeCard = close;
        return ListenableBuilder(
          listenable: widget.controller,
          builder: (_, _) {
            // The latest copy, so a new status or an answered request shows
            // at once. One that is gone keeps its last copy for the frame
            // before the card closes.
            final current =
                widget.controller.relationships
                    .where((item) => item.user.id == relationship.user.id)
                    .firstOrNull ??
                relationship;
            return ProfileCard(
              data: ProfileCardData.relationship(current),
              actions: _profileActions(current, close),
            );
          },
        );
      },
    );
    _closeCard = null;
    if (mounted) setState(() => _openUserId = null);
  }

  /// Copy the id, and for a friend the message field: it opens the DM and
  /// sends what was typed.
  ProfileCardActions _profileActions(
    DiscordRelationship relationship,
    VoidCallback close,
  ) {
    final user = relationship.user;
    final dm = DiscordSocialDmScope.of(context);
    return ProfileCardActions(
      onMessage: relationship.kind == DiscordRelationshipKind.friend
          ? (text) {
              close();
              widget.onMessage(user);
              if (text.isNotEmpty) unawaited(dm.sendMessage(user.id, text));
            }
          : null,
      menu: [
        ProfileCardMenuEntry(
          key: const ValueKey('copy-friend-id'),
          label: 'Copy user ID',
          icon: FlucordIcons.id,
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: user.id))),
        ),
      ],
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
    required this.selected,
    required this.onProfile,
    required this.onMessage,
  });

  final DiscordFriendsController controller;
  final DiscordRelationship relationship;
  final bool selected;
  final ValueChanged<BuildContext> onProfile;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final user = relationship.user;
    final mutationFailed = controller.mutationErrorFor(user.id) != null;
    return Material(
      key: ValueKey('discord-friend-${user.id}'),
      color: selected ? context.surfaces.quietFill : Colors.transparent,
      borderRadius: FlucordRadius.control,
      child: Semantics(
        button: true,
        label: '${user.displayName}, ${_relationshipDetail(relationship)}',
        child: InkWell(
          onTap: () => onProfile(context),
          borderRadius: FlucordRadius.control,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.surfaces.border)),
            ),
            child: Row(
              children: [
                DiscordRelationshipAvatar(user: user, size: 32),
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
                        style: FlucordTextRole.label.style.copyWith(
                          color: context.surfaces.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mutationFailed
                            ? 'Relationship action failed · Try again'
                            : _relationshipDetail(relationship),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlucordTextRole.caption.style.copyWith(
                          color: mutationFailed
                              ? context.surfaces.errorText
                              : context.surfaces.muted,
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
        ),
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
  final FlucordIconData? icon;
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
            else if (icon case final icon?)
              FlucordIcon(icon, size: 28, color: context.surfaces.muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: FlucordTextRole.heading.style.copyWith(
                color: context.surfaces.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: FlucordTextRole.label.style.copyWith(
                color: context.surfaces.muted,
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
          DiscordPresenceStatus.online => _availableDetail(user, 'Online'),
          DiscordPresenceStatus.idle => _availableDetail(user, 'Idle'),
          DiscordPresenceStatus.doNotDisturb => _availableDetail(
            user,
            'Do Not Disturb',
          ),
          DiscordPresenceStatus.offline => 'Offline',
          DiscordPresenceStatus.unknown =>
            user.username ?? 'Status unavailable',
        },
      } +
      suffix;
}

String _availableDetail(DiscordRelationshipUser user, String fallback) {
  final activity = user.activity;
  return activity == null ? fallback : 'Playing ${activity.name}';
}
