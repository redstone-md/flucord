import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/discord_friends_controller.dart';
import '../../domain/discord_relationship.dart';
import '../../theme/flucord_theme.dart';
import 'discord_friend_actions.dart';
import 'discord_friend_profile_popover.dart';
import 'discord_account_connection_scope.dart';
import 'discord_friends_scope.dart';
import 'discord_relationship_avatar.dart';
import 'discord_social_sdk_scope.dart';
import 'discord_social_dm_navigation_scope.dart';
import 'discord_social_dm_scope.dart';

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
  final OverlayPortalController _overlayController = OverlayPortalController();
  final Map<String, LayerLink> _relationshipLinks = {};
  DiscordRelationship? _selectedRelationship;
  LayerLink? _selectedLink;
  bool _openUp = false;
  double _offsetX = 52;

  @override
  void didUpdateWidget(covariant _ReadyFriendDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedId = _selectedRelationship?.user.id;
    if (selectedId != null) {
      final matches = widget.relationships.where(
        (item) => item.user.id == selectedId,
      );
      if (matches.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _dismiss();
        });
      } else {
        _selectedRelationship = matches.first;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(widget.relationships);
    if (items.isEmpty) {
      return const _FriendsState(
        key: ValueKey('discord-friends-empty'),
        icon: Icons.people_outline,
        title: 'No friends to show',
        detail: 'Discord returned no friend or pending-request relationships.',
      );
    }
    _relationshipLinks.removeWhere(
      (id, _) => !widget.relationships.any((item) => item.user.id == id),
    );
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: _buildOverlay,
      child: ListView.builder(
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
          final DiscordRelationship relationship => _rowFor(relationship),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  Widget _rowFor(DiscordRelationship relationship) {
    final userId = relationship.user.id;
    final link = _relationshipLinks.putIfAbsent(userId, LayerLink.new);
    return _FriendRow(
      controller: widget.controller,
      relationship: relationship,
      link: link,
      selected: userId == _selectedRelationship?.user.id,
      onProfile: (context) => _showProfile(context, relationship, link),
      onMessage: () => widget.onMessage(relationship.user),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final relationship = _selectedRelationship;
    final link = _selectedLink;
    if (relationship == null || link == null) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          targetAnchor: _openUp ? Alignment.bottomLeft : Alignment.topLeft,
          followerAnchor: _openUp ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(_offsetX, 0),
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _dismiss();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: DiscordFriendProfilePopover(
              relationship: relationship,
              onMessage: () {
                _dismiss();
                widget.onMessage(relationship.user);
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showProfile(
    BuildContext context,
    DiscordRelationship relationship,
    LayerLink link,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final centerY = origin.dy + (box?.size.height ?? 0) / 2;
    final viewport = MediaQuery.sizeOf(context);
    final maxProfileLeft = viewport.width <= 316 ? 8.0 : viewport.width - 308;
    final profileLeft = (origin.dx + 52).clamp(8.0, maxProfileLeft);
    setState(() {
      _selectedRelationship = relationship;
      _selectedLink = link;
      _openUp = centerY > viewport.height / 2;
      _offsetX = profileLeft - origin.dx;
    });
    _overlayController.show();
  }

  void _dismiss() {
    _overlayController.hide();
    if (!mounted) return;
    setState(() {
      _selectedRelationship = null;
      _selectedLink = null;
    });
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
    required this.link,
    required this.selected,
    required this.onProfile,
    required this.onMessage,
  });

  final DiscordFriendsController controller;
  final DiscordRelationship relationship;
  final LayerLink link;
  final bool selected;
  final ValueChanged<BuildContext> onProfile;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final user = relationship.user;
    final mutationFailed = controller.mutationErrorFor(user.id) != null;
    return CompositedTransformTarget(
      link: link,
      child: Material(
        key: ValueKey('discord-friend-${user.id}'),
        color: selected ? context.surfaces.raised : Colors.transparent,
        child: Semantics(
          button: true,
          label: '${user.displayName}, ${_relationshipDetail(relationship)}',
          child: InkWell(
            onTap: () => onProfile(context),
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.surfaces.border)),
              ),
              child: Row(
                children: [
                  DiscordRelationshipAvatar(user: user),
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
