import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/user_profile.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'activity_views.dart';
import 'flucord_icon_button.dart';
import 'flucord_menu.dart';
import 'name_tags.dart';
import 'popup_anchor.dart';
import 'presence_indicator.dart';
import 'profile_card_data.dart';
import 'recessed_field.dart';
import 'remote_identity_image.dart';

part 'profile_card_parts.dart';
part 'profile_card_preview.dart';

/// What the person looking at a card can do from it. Each action the host
/// leaves out takes its control off the card.
@immutable
final class ProfileCardActions {
  const ProfileCardActions({
    this.onMessage,
    this.onAddFriend,
    this.onAddRole,
    this.addableRoles = const [],
    this.menu = const [],
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

  /// The rows of the banner's "more" menu.
  final List<ProfileCardMenuEntry> menu;
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

  final String label;
  final FlucordIconData icon;
  final VoidCallback onSelected;
  final bool danger;
  final Key? key;
}

/// The profile card: one person, drawn the way Discord's popout draws them.
///
/// Every host opens this same card: member list rows, message authors,
/// voice seats and friend rows. It is 300 wide and scrolls when the window
/// is shorter than it.
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
  static const _bannerHeight = 72.0;
  static const _avatarSize = 80.0;
  static const _ring = 4.0;
  static const _avatarTop = 32.0;
  static const _padding = 16.0;

  final ProfileCardData data;
  final ProfileCardActions actions;

  /// The moment the activity's elapsed time is measured against. Read once
  /// when the card opens unless a test pins it.
  final DateTime? now;

  final bool _preview;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final roles = data.roles;
    final showsRoles =
        roles != null && (roles.isNotEmpty || actions.onAddRole != null);
    final screen = MediaQuery.sizeOf(context);
    // The popout is a route of its own; the preview is part of the page.
    final opensAsRoute = _preview ? null : true;
    return Semantics(
      scopesRoute: opensAsRoute,
      namesRoute: opensAsRoute,
      explicitChildNodes: true,
      label: '${data.displayName} profile',
      child: Material(
        key: const ValueKey('profile-card'),
        color: surfaces.raised,
        elevation: _preview ? 0 : 12,
        shadowColor: FlucordFixedColors.shadow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: FlucordRadius.overlay,
          side: BorderSide(color: surfaces.border),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width.clamp(0.0, screen.width - 16),
            maxHeight: (screen.height - 16).clamp(0.0, double.infinity),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(data: data, actions: actions),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _padding,
                    12,
                    _padding,
                    _padding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _spaced([
                      _Names(data: data),
                      if (_preview)
                        _AboutSections(data: data)
                      else if (data.bio.isNotEmpty)
                        _Bio(bio: data.bio),
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
                        ),
                      if (actions.onMessage case final send?)
                        _MessageField(name: data.displayName, onSubmit: send),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> children) => [
    for (var index = 0; index < children.length; index++) ...[
      if (index > 0) const SizedBox(height: 12),
      children[index],
    ],
  ];
}

/// The banner with its buttons, the avatar over its bottom edge and the
/// custom status beside the avatar.
class _Header extends StatelessWidget {
  const _Header({required this.data, required this.actions});

  final ProfileCardData data;
  final ProfileCardActions actions;

  static const _height =
      ProfileCard._avatarTop + ProfileCard._avatarSize + ProfileCard._ring;
  static const _statusLeft =
      ProfileCard._padding + ProfileCard._avatarSize + ProfileCard._ring + 8;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final accent = data.accentColorValue;
    return SizedBox(
      height: _height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: ProfileCard._bannerHeight,
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
            left: ProfileCard._padding - ProfileCard._ring,
            top: ProfileCard._avatarTop - ProfileCard._ring,
            child: _Avatar(data: data),
          ),
          if (data.customStatus case final status?)
            Positioned(
              left: _statusLeft,
              right: ProfileCard._padding,
              top: ProfileCard._bannerHeight - 14,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _StatusBubble(text: status),
              ),
            ),
        ],
      ),
    );
  }
}

/// An 80 px avatar in a ring of the card's colour, with its decoration and
/// the status dot.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.data});

  final ProfileCardData data;

  static const _outer = ProfileCard._avatarSize + 2 * ProfileCard._ring;
  static const _decoration = ProfileCard._avatarSize * 1.2;
  static const _dot = 16.0;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final colorValue = data.avatarColorValue;
    return SizedBox.square(
      dimension: _outer,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: surfaces.raised,
            ),
            child: Padding(
              padding: const EdgeInsets.all(ProfileCard._ring),
              child: ClipOval(
                child: RemoteIdentityImage(
                  url: data.avatarUrl,
                  fallback: ColoredBox(
                    color: colorValue == null
                        ? surfaces.control
                        : Color(colorValue),
                    child: Center(
                      child: Text(
                        data.monogram,
                        style: FlucordTextRole.display.style.copyWith(
                          color: FlucordFixedColors.onFill,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (data.decorationUrl case final url?)
            SizedBox.square(
              dimension: _decoration,
              child: RemoteIdentityImage(
                key: const ValueKey('profile-card-decoration'),
                url: url,
                fallback: const SizedBox.shrink(),
              ),
            ),
          if (data.presence case final presence?)
            Positioned(
              right: ProfileCard._ring,
              bottom: ProfileCard._ring,
              child: PresenceIndicator(
                presence: presence,
                size: _dot + 6,
                borderWidth: 3,
                borderColor: surfaces.raised,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBubble extends StatelessWidget {
  const _StatusBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Container(
      key: const ValueKey('profile-card-custom-status'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: surfaces.raised,
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

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.entries});

  final List<ProfileCardMenuEntry> entries;

  Future<void> _open(BuildContext context) async {
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

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => _BannerButton(
      key: const ValueKey('profile-card-more'),
      icon: FlucordIcons.more,
      tooltip: 'More',
      onPressed: () => _open(context),
    ),
  );
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
    return TextField(
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),
          ),
    );
  }
}
