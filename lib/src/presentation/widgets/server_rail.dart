import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/read_state.dart';
import '../../domain/workspace_activity.dart';
import '../../application/connection_controller.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';
import 'account_standing_scope.dart';
import 'auth_session_scope.dart';
import 'age_verification_scope.dart';
import 'keybind_scope.dart';
import 'streamer_mode_scope.dart';
import 'theme_scope.dart';
import 'multi_factor_auth_scope.dart';
import 'family_centre_scope.dart';
import 'user_profile_scope.dart';
import 'user_settings_dialog.dart';
import 'user_settings_scope.dart';

class ServerRail extends StatelessWidget {
  const ServerRail({
    required this.workspace,
    required this.selectedSpaceId,
    required this.onSelectSpace,
    required this.onToggleTheme,
    required this.onOpenConnections,
    required this.sessionMode,
    required this.isDark,
    this.readState,
    super.key,
  });

  final ChatWorkspace workspace;
  final String selectedSpaceId;
  final ValueChanged<String> onSelectSpace;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenConnections;
  final SessionMode sessionMode;
  final bool isDark;

  /// The server's read state, when the transport has one. It decides which
  /// channels count towards a pip and which spaces are muted.
  final ReadStateSnapshot? readState;

  @override
  Widget build(BuildContext context) {
    final directSpaces = workspace.spaces.where(
      (space) => space.isDirectMessages,
    );
    final directSpace = directSpaces.isEmpty ? null : directSpaces.first;
    final guildSpaces = workspace.spaces
        .where((space) => !space.isDirectMessages)
        .toList(growable: false);
    final activityBySpaceId = workspace.activityBySpace(readState: readState);
    return Container(
      key: const ValueKey('server-rail'),
      width: 72,
      decoration: BoxDecoration(
        color: context.surfaces.rail,
        border: Border(right: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          _HomeButton(
            selected: directSpace?.id == selectedSpaceId,
            activity: directSpace == null
                ? SpaceActivity.none
                : activityBySpaceId[directSpace.id] ?? SpaceActivity.none,
            onPressed: directSpace == null
                ? null
                : () => onSelectSpace(directSpace.id),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, indent: 18, endIndent: 18),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: guildSpaces.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final space = guildSpaces[index];
                return _SpaceButton(
                  space: space,
                  selected: space.id == selectedSpaceId,
                  activity: activityBySpaceId[space.id] ?? SpaceActivity.none,
                  onPressed: () => onSelectSpace(space.id),
                );
              },
            ),
          ),
          IconButton(
            key: const ValueKey('open-connections'),
            onPressed: onOpenConnections,
            icon: Icon(
              sessionMode == SessionMode.discord
                  ? Icons.link
                  : Icons.link_outlined,
              color: sessionMode == SessionMode.discord
                  ? FlucordColors.brand
                  : null,
            ),
            tooltip: 'Connections',
          ),
          IconButton(
            onPressed: onToggleTheme,
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode),
            tooltip: isDark ? 'Use light theme' : 'Use dark theme',
          ),
          // The settings controller is read from the scope rather than passed
          // down: the gear belongs next to the other rail actions, and a host
          // that installs no scope — the single-pane widget tests — has no
          // account to show settings for anyway.
          if (UserSettingsScope.maybeOf(context) case final settings?)
            IconButton(
              key: const ValueKey('open-user-settings'),
              onPressed: () => unawaited(
                UserSettingsDialog.show(
                  context,
                  controller: settings,
                  profileController: UserProfileScope.maybeOf(context),
                  standingController: AccountStandingScope.maybeOf(context),
                  familyController: FamilyCentreScope.maybeOf(context),
                  sessionController: AuthSessionScope.maybeOf(context),
                  mfaController: MultiFactorAuthScope.maybeOf(context),
                  ageController: AgeVerificationScope.maybeOf(context),
                  keybindController: KeybindScope.maybeOf(context),
                  streamerModeController: StreamerModeScope.maybeOf(
                    context,
                  ),
                  themeController: ThemeScope.maybeOf(context),
                ),
              ),
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'User settings',
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  const _HomeButton({
    required this.selected,
    required this.activity,
    required this.onPressed,
  });

  final bool selected;
  final SpaceActivity activity;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => _RailButton(
    spaceId: CommunitySpace.directMessagesId,
    buttonKey: const ValueKey('space-direct-messages'),
    selected: selected,
    activity: activity,
    onPressed: onPressed,
    tooltip: onPressed == null ? 'Flucord' : 'Direct Messages',
    idleColor: context.surfaces.raised,
    activeColor: FlucordColors.brand,
    builder: (context, active) => Icon(
      Icons.forum_rounded,
      size: 21,
      color: active ? Colors.white : context.surfaces.muted,
    ),
  );
}

class _SpaceButton extends StatelessWidget {
  const _SpaceButton({
    required this.space,
    required this.selected,
    required this.activity,
    required this.onPressed,
  });

  final CommunitySpace space;
  final bool selected;
  final SpaceActivity activity;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => _RailButton(
    spaceId: space.id,
    buttonKey: ValueKey('space-${space.id}'),
    selected: selected,
    activity: activity,
    onPressed: onPressed,
    tooltip: space.name,
    idleColor: Color(space.colorValue).withValues(alpha: 0.62),
    activeColor: Color(space.colorValue),
    builder: (_, _) => RemoteIdentityImage(
      url: space.iconUrl,
      imageKey: ValueKey('space-icon-${space.id}'),
      fallback: Center(
        child: Text(
          space.monogram,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

typedef _RailButtonBuilder = Widget Function(BuildContext context, bool active);

class _RailButton extends StatefulWidget {
  const _RailButton({
    required this.spaceId,
    required this.buttonKey,
    required this.selected,
    required this.activity,
    required this.onPressed,
    required this.tooltip,
    required this.idleColor,
    required this.activeColor,
    required this.builder,
  });

  final String spaceId;
  final Key buttonKey;
  final bool selected;
  final SpaceActivity activity;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color idleColor;
  final Color activeColor;
  final _RailButtonBuilder builder;

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    final radius = BorderRadius.circular(active ? 14 : 22);
    final semanticsLabel = _activityLabel(widget.tooltip, widget.activity);
    return Semantics(
      key: ValueKey('space-semantics-${widget.spaceId}'),
      label: semanticsLabel,
      button: widget.onPressed != null,
      enabled: widget.onPressed != null,
      selected: widget.selected,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: SizedBox(
        height: 46,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.selected || widget.activity.hasUnread)
              Positioned(
                left: 0,
                child: SizedBox(
                  key: ValueKey('space-indicator-${widget.spaceId}'),
                  width: 3,
                  height: widget.selected ? 28 : 8,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            Tooltip(
              message: semanticsLabel,
              excludeFromSemantics: true,
              preferBelow: false,
              child: MouseRegion(
                onEnter: (_) {
                  if (widget.onPressed != null) {
                    setState(() => _hovered = true);
                  }
                },
                onExit: (_) => setState(() => _hovered = false),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: radius,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: widget.buttonKey,
                    onTap: widget.onPressed,
                    borderRadius: radius,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: active ? widget.activeColor : widget.idleColor,
                        borderRadius: radius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      // A muted space keeps its icon but loses its emphasis;
                      // the mention badge below still shows through at full
                      // strength, because a mention outranks a mute.
                      child: Opacity(
                        opacity: widget.activity.muted && !active ? 0.45 : 1,
                        child: widget.builder(context, active),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.activity.mentionCount > 0)
              Positioned(
                right: 4,
                bottom: 0,
                child: _MentionBadge(
                  spaceId: widget.spaceId,
                  count: widget.activity.mentionCount,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _activityLabel(String name, SpaceActivity activity) {
    if (activity.mentionCount == 1) return '$name, 1 mention';
    if (activity.mentionCount > 1) {
      return '$name, ${activity.mentionCount} mentions';
    }
    if (activity.muted) return '$name, muted';
    return activity.hasUnread ? '$name, unread' : name;
  }
}

class _MentionBadge extends StatelessWidget {
  const _MentionBadge({required this.spaceId, required this.count});

  final String spaceId;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('space-mention-$spaceId'),
    constraints: const BoxConstraints(minWidth: 18),
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: FlucordColors.mention,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: context.surfaces.rail, width: 2),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
