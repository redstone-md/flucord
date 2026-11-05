import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../data/discord/discord_cdn.dart';
import '../../domain/chat_models.dart';
import '../../domain/monogram.dart';
import '../../domain/user_profile.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'activity_views.dart';
import 'display_name.dart';
import 'art_tile.dart';
import 'chat_scope.dart';
import 'discord_markdown.dart';
import 'flucord_button.dart';
import 'flucord_controls.dart';
import 'flucord_dialog.dart';
import 'flucord_icon_button.dart';
import 'flucord_menu.dart';
import 'member_avatar.dart';
import 'motion_scope.dart';
import 'name_tags.dart';
import 'overlapping_faces.dart';
import 'popup_anchor.dart';
import 'presence_indicator.dart';
import 'profile_card_data.dart';
import 'profile_card_route.dart';
import 'profile_effect_overlay.dart';
import 'profile_theme.dart';
import 'recessed_field.dart';
import 'remote_identity_image.dart';
import 'service_logo.dart';

part 'profile_card_chips.dart';
part 'profile_card_full.dart';
part 'profile_card_full_side.dart';
part 'profile_card_parts.dart';
part 'profile_card_preview.dart';

/// What the person looking at a card or the full profile can do from it.
/// Each action the host leaves out takes its control away.
@immutable
final class ProfileCardActions {
  const ProfileCardActions({
    this.onMessage,
    this.onAddFriend,
    this.onAddRole,
    this.addableRoles = const [],
    this.onRemoveRole,
    this.removableRoleIds = const {},
    this.menu = const [],
    this.onOpenFullProfile,
    this.onOpenProfile,
    this.onOpenServer,
    this.onJoinVoice,
    this.onOpenLink,
  });

  /// Opens the DM with what was typed in the message field.
  final ValueChanged<String>? onMessage;

  /// Sends a friend request. Absent for a friend, a pending request and the
  /// account itself.
  final VoidCallback? onAddFriend;

  /// Gives the person a role. Present only for someone who can manage roles.
  final ValueChanged<CommunityRole>? onAddRole;

  /// The roles [onAddRole] may give.
  final List<CommunityRole> addableRoles;

  /// Takes a role away from the person. Present only for someone who can
  /// manage roles.
  final ValueChanged<CommunityRole>? onRemoveRole;

  /// The ids of the held roles [onRemoveRole] may take away.
  final Set<String> removableRoleIds;

  /// The rows of the "more" menu.
  final List<ProfileCardMenuEntry> menu;

  /// Opens the full profile window. The card's avatar, its name and "View
  /// full bio" call it.
  final VoidCallback? onOpenFullProfile;

  /// Opens a mutual friend's card beside their row.
  final OpenProfileCard? onOpenProfile;

  /// Opens a mutual server, by id.
  final ValueChanged<String>? onOpenServer;

  /// Opens the voice channel the person sits in, by id.
  final ValueChanged<String>? onJoinVoice;

  /// Opens a linked account's page.
  final ValueChanged<Uri>? onOpenLink;
}

/// One row of the card's "more" menu.
@immutable
final class ProfileCardMenuEntry {
  const ProfileCardMenuEntry({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.danger = false,
    this.key,
  });

  /// "Copy user ID", which every card offers.
  ProfileCardMenuEntry.copyUserId(String userId, {Key? key})
    : this(
        key: key,
        label: 'Copy user ID',
        icon: FlucordIcons.id,
        onSelected: () =>
            unawaited(Clipboard.setData(ClipboardData(text: userId))),
      );

  final String label;
  final FlucordIconData icon;
  final VoidCallback onSelected;
  final bool danger;
  final Key? key;
}

/// The profile card: one person, drawn the way Discord's popout draws them.
///
/// Every host opens this same card: member list rows, message authors,
/// voice seats and friend rows. It scrolls when the window is shorter than
/// it.
class ProfileCard extends StatelessWidget {
  const ProfileCard({
    required this.data,
    this.actions = const ProfileCardActions(),
    this.now,
    super.key,
  }) : _preview = false;

  /// The account's own card on the profile settings page. It sits flat in
  /// the page with no actions, and shows "About me" and "Member since" under
  /// a divider.
  const ProfileCard.preview({required this.data, super.key})
    : actions = const ProfileCardActions(),
      now = null,
      _preview = true;

  static const width = 300.0;
  static const _padding = 16.0;

  final ProfileCardData data;
  final ProfileCardActions actions;

  /// The moment the activity's elapsed time is measured against. Read once
  /// when the card opens unless a test pins it.
  final DateTime? now;

  final bool _preview;

  @override
  Widget build(BuildContext context) => ProfileTheme(
    colors: data.themeColors,
    child: Builder(builder: _buildCard),
  );

  Widget _buildCard(BuildContext context) {
    final surfaces = context.surfaces;
    final roles = data.roles;
    final showsRoles =
        roles != null && (roles.isNotEmpty || actions.onAddRole != null);
    final screen = MediaQuery.sizeOf(context);
    // The popout is a route of its own; the preview is part of the page.
    final opensAsRoute = _preview ? null : true;
    return MotionHoverRegion(
      // The card is one hover target: its avatar and banner play while the
      // pointer is anywhere on it.
      child: Semantics(
        scopesRoute: opensAsRoute,
        namesRoute: opensAsRoute,
        explicitChildNodes: true,
        label: '${data.displayName} profile',
        child: _CardSurface(
          key: const ValueKey('profile-card'),
          theme: data.themeColors,
          color: surfaces.raised,
          elevation: _preview ? 0 : 12,
          shadowColor: FlucordFixedColors.shadow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: FlucordRadius.overlay,
            side: BorderSide(color: surfaces.border),
          ),
          child: _EffectBox(
            data: data,
            constraints: BoxConstraints(
              maxWidth: width.clamp(0.0, screen.width - 16),
              maxHeight: (screen.height - 16).clamp(0.0, double.infinity),
            ),
            child: SingleChildScrollView(
              child: SelectionArea(
                // Names, the bio and the status can be selected and copied. A click on the name still opens the full profile.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      data: data,
                      metrics: _ProfileMetrics.card,
                      backdrop: surfaces.raised,
                      actions: actions,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _padding,
                        12,
                        _padding,
                        _padding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 12,
                        children: [
                          _Names(
                            data: data,
                            metrics: _ProfileMetrics.card,
                            backdrop: surfaces.raised,
                            onOpenFullProfile: actions.onOpenFullProfile,
                          ),
                          if (_preview)
                            _AboutSections(data: data)
                          else if (data.bio.isNotEmpty)
                            _Bio(
                              bio: data.bio,
                              onViewFull: actions.onOpenFullProfile,
                              onOpenLink: actions.onOpenLink,
                            ),
                          if (data.activity case final activity?)
                            ActivityCard(
                              activity: activity,
                              now: now ?? DateTime.now(),
                            ),
                          if (showsRoles)
                            _Roles(
                              roles: roles,
                              addable: actions.addableRoles,
                              onAdd: actions.onAddRole,
                              removable: actions.removableRoleIds,
                              onRemove: actions.onRemoveRole,
                            ),
                          if (actions.onMessage case final send?)
                            _MessageField(
                              name: data.displayName,
                              onSubmit: send,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's frame: a [Material] that paints the profile's gradient, where
/// it has one, under [child].
class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.theme,
    required this.color,
    required this.elevation,
    required this.shadowColor,
    required this.clipBehavior,
    required this.shape,
    required this.child,
    super.key,
  });

  final ProfileThemeColors? theme;
  final Color color;
  final double elevation;
  final Color shadowColor;
  final Clip clipBehavior;
  final ShapeBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    elevation: elevation,
    shadowColor: shadowColor,
    clipBehavior: clipBehavior,
    shape: shape,
    child: ProfileBackdrop(
      key: const ValueKey('profile-card-theme'),
      color: null,
      colors: theme,
      child: child,
    ),
  );
}

/// The box that holds a card's content: [child] in [constraints], with the
/// profile effect of [data] over it.
class _EffectBox extends StatelessWidget {
  const _EffectBox({
    required this.data,
    required this.child,
    this.constraints = const BoxConstraints(),
  });

  final ProfileCardData data;
  final BoxConstraints constraints;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = switch (data.effect) {
      final effect? => Stack(
        children: [
          child,
          Positioned.fill(
            child: ProfileEffectOverlay(
              effect: effect,
              endsAt: data.effectEndsAt,
            ),
          ),
        ],
      ),
      null => child,
    };
    return ConstrainedBox(constraints: constraints, child: content);
  }
}

/// What differs between the card and the window: the sizes of the banner
/// and the avatar, the name's size, and whether the mutual line shows (the
/// window has tabs for the mutuals instead).
@immutable
final class _ProfileMetrics {
  const _ProfileMetrics({
    required this.bannerHeight,
    required this.imageBannerHeight,
    required this.avatarSize,
    required this.ring,
    required this.padding,
    required this.dot,
    required this.name,
    required this.showsMutualLine,
  });

  static const card = _ProfileMetrics(
    bannerHeight: 72,
    // Discord's popout: 105 px of banner image on a 300 px card.
    imageBannerHeight: 105,
    avatarSize: 80,
    ring: 4,
    padding: ProfileCard._padding,
    dot: 16,
    name: FlucordTextRole.title,
    showsMutualLine: true,
  );

  static const window = _ProfileMetrics(
    bannerHeight: 120,
    imageBannerHeight: 120,
    avatarSize: 96,
    ring: 6,
    padding: 20,
    dot: 18,
    name: FlucordTextRole.display,
    showsMutualLine: false,
  );

  final FlucordTextRole name;
  final bool showsMutualLine;

  /// The banner's height with only a colour in it.
  final double bannerHeight;
  final double imageBannerHeight;
  final double avatarSize;

  /// The band of [_Header.backdrop] around the avatar.
  final double ring;
  final double padding;
  final double dot;

  double get statusLeft => padding + avatarSize + ring + 8;

  double bannerHeightOf(ProfileCardData data) =>
      data.bannerUrl == null ? bannerHeight : imageBannerHeight;
}

/// The banner, the avatar over its bottom edge and the custom status beside
/// the avatar. [actions] put add friend and "more" on the banner and make
/// the avatar open the full profile, as the card has them; the window leaves
/// them out and has its own row.
class _Header extends StatelessWidget {
  const _Header({
    required this.data,
    required this.metrics,
    required this.backdrop,
    this.actions = const ProfileCardActions(),
  });

  final ProfileCardData data;
  final _ProfileMetrics metrics;

  /// The colour the header sits on, which rings the avatar.
  final Color backdrop;
  final ProfileCardActions actions;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final accent = data.accentColorValue;
    // A picture, not text: its fallback letter stays out of a selection.
    final avatar = SelectionContainer.disabled(
      child: _Avatar(data: data, metrics: metrics, backdrop: backdrop),
    );
    final bannerHeight = metrics.bannerHeightOf(data);
    // The avatar's middle sits on the banner's bottom edge.
    final avatarTop = bannerHeight - metrics.avatarSize / 2;
    return SizedBox(
      height: avatarTop + metrics.avatarSize + metrics.ring,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: bannerHeight,
            child: ColoredBox(
              key: const ValueKey('profile-card-banner'),
              color: accent == null ? surfaces.control : Color(accent),
              child: data.bannerUrl == null
                  ? null
                  : RemoteIdentityImage(
                      url: data.bannerUrl,
                      imageKey: const ValueKey('profile-card-banner-image'),
                      fallback: const SizedBox.shrink(),
                    ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              children: [
                if (actions.onAddFriend case final add?)
                  _BannerButton(
                    key: const ValueKey('profile-card-add-friend'),
                    icon: FlucordIcons.addFriend,
                    tooltip: 'Add friend',
                    onPressed: add,
                  ),
                if (actions.onAddFriend != null && actions.menu.isNotEmpty)
                  const SizedBox(width: 8),
                if (actions.menu.isNotEmpty) _MoreButton(entries: actions.menu),
              ],
            ),
          ),
          Positioned(
            left: metrics.padding - metrics.ring,
            top: avatarTop - metrics.ring,
            child: _FullProfileLink(
              linkKey: const ValueKey('profile-card-avatar'),
              name: data.displayName,
              onOpen: actions.onOpenFullProfile,
              child: avatar,
            ),
          ),
          if (data.customStatus case final status?)
            Positioned(
              left: metrics.statusLeft,
              right: metrics.padding,
              top: bannerHeight - 14,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _StatusBubble(text: status, fill: backdrop),
              ),
            ),
        ],
      ),
    );
  }
}

/// The avatar in a ring of the card's colour, with its decoration and the
/// status dot.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.data,
    required this.metrics,
    required this.backdrop,
  });

  final ProfileCardData data;
  final _ProfileMetrics metrics;
  final Color backdrop;

  @override
  Widget build(BuildContext context) {
    final colorValue = data.avatarColorValue;
    return SizedBox.square(
      dimension: metrics.avatarSize + 2 * metrics.ring,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: backdrop),
            child: Padding(
              padding: EdgeInsets.all(metrics.ring),
              child: ClipOval(
                child: ProfileAvatarImage(
                  url: data.avatarUrl,
                  monogram: data.monogram,
                  fill: colorValue == null ? null : Color(colorValue),
                ),
              ),
            ),
          ),
          if (data.decorationUrl case final url?)
            SizedBox.square(
              dimension: metrics.avatarSize * MemberAvatar.decorationScale,
              child: RemoteIdentityImage(
                key: const ValueKey('profile-card-decoration'),
                url: url,
                fallback: const SizedBox.shrink(),
              ),
            ),
          if (data.presence case final presence?)
            Positioned(
              right: metrics.ring,
              bottom: metrics.ring,
              child: PresenceIndicator(
                presence: presence,
                size: metrics.dot + 6,
                borderWidth: 3,
                borderColor: backdrop,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBubble extends StatelessWidget {
  const _StatusBubble({required this.text, required this.fill});

  final String text;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Container(
      key: const ValueKey('profile-card-custom-status'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: FlucordRadius.large,
        border: Border.all(color: surfaces.border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FlucordTextRole.caption.style.copyWith(color: surfaces.bodyText),
      ),
    );
  }
}

/// A round button over the banner, on a dark scrim so it reads on any
/// banner image.
class _BannerButton extends StatelessWidget {
  const _BannerButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  static const _size = 28.0;

  final FlucordIconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: FlucordFixedColors.scrim,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: _size,
          child: Center(
            child: FlucordIcon(
              icon,
              size: 16,
              color: FlucordFixedColors.onFill,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Opens [entries] under the widget at [context] and runs the chosen one.
Future<void> _openMenu(
  BuildContext context,
  List<ProfileCardMenuEntry> entries,
) async {
  final chosen = await showMenu<ProfileCardMenuEntry>(
    context: context,
    position: menuBelow(context),
    items: [
      for (final entry in entries)
        FlucordMenuItem(
          key: entry.key,
          value: entry,
          icon: entry.icon,
          label: entry.label,
          danger: entry.danger,
        ),
    ],
  );
  chosen?.onSelected();
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.entries});

  final List<ProfileCardMenuEntry> entries;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => _BannerButton(
      key: const ValueKey('profile-card-more'),
      icon: FlucordIcons.more,
      tooltip: 'More',
      onPressed: () => _openMenu(context, entries),
    ),
  );
}

/// Makes [child] open [name]'s full profile: a pointer, a click and a
/// button to assistive technology. Without [onOpen] it is only [child].
class _FullProfileLink extends StatelessWidget {
  const _FullProfileLink({
    required this.linkKey,
    required this.name,
    required this.onOpen,
    required this.child,
  });

  /// The link's key, on the link only, so a finder sees no link when there
  /// is none.
  final Key linkKey;
  final String name;
  final VoidCallback? onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) => switch (onOpen) {
    final open? => Semantics(
      key: linkKey,
      button: true,
      label: 'View $name full profile',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: open, child: child),
      ),
    ),
    null => child,
  };
}

/// The "Message @name" field. Enter opens the DM with the text.
class _MessageField extends StatefulWidget {
  const _MessageField({required this.name, required this.onSubmit});

  final String name;
  final ValueChanged<String> onSubmit;

  @override
  State<_MessageField> createState() => _MessageFieldState();
}

class _MessageFieldState extends State<_MessageField> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return SelectionContainer.disabled(
      // Its hint is a prompt, not profile text.
      child: TextField(
        key: const ValueKey('profile-card-message'),
        controller: _text,
        textInputAction: TextInputAction.send,
        onSubmitted: (text) => widget.onSubmit(text.trim()),
        style: FlucordTextRole.label.style.copyWith(color: surfaces.text),
        // Framed, as the activity card above it: siblings share a corner.
        decoration:
            recessedFieldDecoration(
              context,
              borderRadius: FlucordRadius.framed,
            ).copyWith(
              hintText: 'Message @${widget.name}',
              hintStyle: FlucordTextRole.label.style.copyWith(
                color: surfaces.captionText,
              ),
              // 9 + 18 + 9: the label line in the middle of a 36 px field,
              // as the app's other fields have it.
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
            ),
      ),
    );
  }
}
