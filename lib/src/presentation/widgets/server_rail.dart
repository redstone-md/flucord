import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/workspace_activity.dart';
import '../../application/connection_controller.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import 'account_connections_scope.dart';
import 'account_entitlements_scope.dart';
import 'account_data_package_scope.dart';
import 'app_authorisation_scope.dart';
import 'auth_session_scope.dart';
import 'account_standing_scope.dart';
import 'remote_identity_image.dart';

import 'accessibility_scope.dart';
import 'activity_label.dart';
import 'age_verification_scope.dart';
import 'keybind_scope.dart';
import 'count_badge.dart';
import 'stream_quality_scope.dart';
import 'streamer_mode_scope.dart';
import 'theme_scope.dart';
import 'voice_scope.dart';
import 'multi_factor_auth_scope.dart';
import 'family_centre_scope.dart';
import 'rail_tile.dart';
import 'user_profile_scope.dart';
import 'user_settings_dialog.dart';
import 'user_settings_scope.dart';

class ServerRail extends StatelessWidget {
  const ServerRail({
    required this.spaces,
    required this.activity,
    required this.selectedSpaceId,
    required this.onSelectSpace,
    required this.onToggleTheme,
    required this.onOpenConnections,
    required this.sessionMode,
    required this.isDark,
    this.onAddServer,
    this.onOpenSpaceMenu,
    super.key,
  });

  final List<CommunitySpace> spaces;

  /// What each space has waiting, already rolled up. Taken ready-made rather
  /// than rolled up here so the rail's inputs are small enough to compare,
  /// which is what lets the shell keep the rail across a rebuild that did not
  /// move any pip.
  final Map<String, SpaceActivity> activity;

  final String selectedSpaceId;
  final ValueChanged<String> onSelectSpace;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenConnections;
  final SessionMode sessionMode;
  final bool isDark;

  /// Opens the add-server surface, or null on a transport that cannot join,
  /// create or leave anything. The button is hidden rather than disabled:
  /// a plus that can do nothing is a lie about what the app offers.
  final VoidCallback? onAddServer;

  /// Opens the menu of a server at a global position, on a right click.
  final void Function(String spaceId, Offset position)? onOpenSpaceMenu;

  @override
  Widget build(BuildContext context) {
    final directSpaces = spaces.where((space) => space.isDirectMessages);
    final directSpace = directSpaces.isEmpty ? null : directSpaces.first;
    final guildSpaces = spaces
        .where((space) => !space.isDirectMessages)
        .toList(growable: false);
    return Container(
      key: const ValueKey('server-rail'),
      width: RailMetrics.width,
      color: context.surfaces.rail,
      child: Column(
        children: [
          const SizedBox(height: RailMetrics.gap),
          _HomeButton(
            selected: directSpace?.id == selectedSpaceId,
            activity: directSpace == null
                ? SpaceActivity.none
                : activity[directSpace.id] ?? SpaceActivity.none,
            onPressed: directSpace == null
                ? null
                : () => onSelectSpace(directSpace.id),
          ),
          const RailDivider(),
          Expanded(
            child: ListView.separated(
              // Room for the badge that hangs below the last tile.
              padding: const EdgeInsets.only(bottom: RailMetrics.gap),
              itemCount: guildSpaces.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: RailMetrics.gap),
              itemBuilder: (context, index) {
                final space = guildSpaces[index];
                return _SpaceButton(
                  space: space,
                  selected: space.id == selectedSpaceId,
                  activity: activity[space.id] ?? SpaceActivity.none,
                  onPressed: () => onSelectSpace(space.id),
                  onOpenMenu: onOpenSpaceMenu == null
                      ? null
                      : (position) => onOpenSpaceMenu!(space.id, position),
                );
              },
            ),
          ),
          if (onAddServer != null)
            Padding(
              padding: const EdgeInsets.only(bottom: RailMetrics.gap),
              child: _AddServerButton(onPressed: onAddServer!),
            ),
          IconButton(
            key: const ValueKey('open-connections'),
            onPressed: onOpenConnections,
            icon: FlucordIcon(
              FlucordIcons.link,
              color: sessionMode == SessionMode.discord
                  ? context.surfaces.accentIcon
                  : null,
            ),
            tooltip: 'Connections',
          ),
          RailThemeToggle(isDark: isDark, onPressed: onToggleTheme),
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
                  connectionsController: AccountConnectionsScope.maybeOf(
                    context,
                  ),
                  entitlementsController: AccountEntitlementsScope.maybeOf(
                    context,
                  ),
                  dataPackageController: AccountDataPackageScope.maybeOf(
                    context,
                  ),
                  appAuthorisationController: AppAuthorisationScope.maybeOf(
                    context,
                  ),
                  mfaController: MultiFactorAuthScope.maybeOf(context),
                  ageController: AgeVerificationScope.maybeOf(context),
                  keybindController: KeybindScope.maybeOf(context),
                  streamerModeController: StreamerModeScope.maybeOf(context),
                  accessibilityController: AccessibilityScope.maybeOf(context),
                  streamQualityController: StreamQualityScope.maybeOf(context),
                  themeController: ThemeScope.maybeOf(context),
                  voiceController: VoiceScope.maybeOf(context),
                ),
              ),
              icon: const FlucordIcon(FlucordIcons.settings),
              tooltip: 'User settings',
            ),
          const SizedBox(height: RailMetrics.gap),
        ],
      ),
    );
  }
}

/// The add-server entry at the foot of the space list: an outlined tile, so
/// it reads as an action rather than as one more server.
class _AddServerButton extends StatelessWidget {
  const _AddServerButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => RailTile(
    tileKey: const ValueKey('add-server'),
    label: 'Add a server',
    onPressed: onPressed,
    activeColor: context.surfaces.control,
    builder: (context, active) => Center(
      child: FlucordIcon(
        FlucordIcons.add,
        size: RailMetrics.glyph,
        color: active ? context.surfaces.text : context.surfaces.muted,
      ),
    ),
  );
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
  Widget build(BuildContext context) => _SpaceTile(
    spaceId: CommunitySpace.directMessagesId,
    tileKey: const ValueKey('space-direct-messages'),
    name: onPressed == null ? 'Flucord' : 'Direct Messages',
    selected: selected,
    activity: activity,
    onPressed: onPressed,
    color: context.surfaces.raised,
    activeColor: context.surfaces.brand,
    builder: (context, active) => Center(
      child: FlucordIcon(
        FlucordIcons.directMessages,
        size: RailMetrics.glyph,
        color: active
            ? Theme.of(context).colorScheme.onPrimary
            : context.surfaces.muted,
      ),
    ),
  );
}

class _SpaceButton extends StatelessWidget {
  const _SpaceButton({
    required this.space,
    required this.selected,
    required this.activity,
    required this.onPressed,
    required this.onOpenMenu,
  });

  final CommunitySpace space;
  final bool selected;
  final SpaceActivity activity;
  final VoidCallback onPressed;
  final ValueChanged<Offset>? onOpenMenu;

  @override
  Widget build(BuildContext context) => _SpaceTile(
    spaceId: space.id,
    tileKey: ValueKey('space-${space.id}'),
    name: space.name,
    selected: selected,
    activity: activity,
    onPressed: onPressed,
    onOpenMenu: onOpenMenu,
    color: Color(space.colorValue).withValues(alpha: 0.62),
    activeColor: Color(space.colorValue),
    builder: (_, _) => RemoteIdentityImage(
      url: space.iconUrl,
      imageKey: ValueKey('space-icon-${space.id}'),
      animatesOnHover: true,
      fallback: RailMonogram(space.monogram),
    ),
  );
}

/// A space on the rail: its pill shows whether it is open or unread, and its
/// badge counts the mentions waiting there.
class _SpaceTile extends StatelessWidget {
  const _SpaceTile({
    required this.spaceId,
    required this.tileKey,
    required this.name,
    required this.selected,
    required this.activity,
    required this.onPressed,
    required this.color,
    required this.activeColor,
    required this.builder,
    this.onOpenMenu,
  });

  final String spaceId;
  final Key tileKey;
  final String name;
  final bool selected;
  final SpaceActivity activity;
  final VoidCallback? onPressed;
  final ValueChanged<Offset>? onOpenMenu;
  final Color color;
  final Color activeColor;
  final Widget Function(BuildContext context, bool active) builder;

  @override
  Widget build(BuildContext context) => RailTile(
    key: ValueKey('space-semantics-$spaceId'),
    tileKey: tileKey,
    label: activityLabel(
      name,
      mentionCount: activity.mentionCount,
      muted: activity.muted,
      unread: activity.hasUnread,
    ),
    onPressed: onPressed,
    onOpenMenu: onOpenMenu,
    selected: selected,
    pill: selected
        ? RailPill.selected
        : activity.hasUnread
        ? RailPill.unread
        : RailPill.none,
    pillKey: ValueKey('space-indicator-$spaceId'),
    color: color,
    activeColor: activeColor,
    dimmed: activity.muted,
    badge: activity.mentionCount > 0
        ? CountBadge(
            key: ValueKey('space-mention-$spaceId'),
            count: activity.mentionCount,
            ring: context.surfaces.rail,
          )
        : null,
    builder: builder,
  );
}
