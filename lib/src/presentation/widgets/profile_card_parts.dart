part of 'profile_card.dart';

/// The name, then the username line, the badges and, in the card, the mutual
/// line. The window has tabs for the mutuals and a larger name.
class _Names extends StatelessWidget {
  const _Names({
    required this.data,
    required this.backdrop,
    this.onOpenFullProfile,
    this.inWindow = false,
  });

  final ProfileCardData data;

  /// The colour the names sit on, which rings the mutual friends' faces.
  final Color backdrop;

  /// A click on the name calls it.
  final VoidCallback? onOpenFullProfile;
  final bool inWindow;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final handle = [
      ?data.username,
      if (data.pronouns.isNotEmpty) data.pronouns,
    ].join(' · ');
    final clan = data.clanTag;
    final name = DisplayName(
      data.displayName,
      maxLines: 2,
      style: (inWindow ? FlucordTextRole.display : FlucordTextRole.title).style
          .copyWith(color: surfaces.text),
      nameStyle: data.nameStyle,
    );
    final showsMutual =
        !inWindow &&
        (data.mutualFriends.isNotEmpty || data.mutualServers.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FullProfileLink(
          linkKey: const ValueKey('profile-card-name'),
          name: data.displayName,
          onOpen: onOpenFullProfile,
          child: name,
        ),
        if (handle.isNotEmpty || clan != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              if (handle.isNotEmpty)
                Flexible(
                  child: Text(
                    handle,
                    key: const ValueKey('profile-card-handle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlucordTextRole.label.style.copyWith(
                      color: surfaces.muted,
                    ),
                  ),
                ),
              if (handle.isNotEmpty && clan != null) const SizedBox(width: 6),
              ?(clan == null ? null : ClanTagChip(clan: clan)),
            ],
          ),
        ],
        if (data.badges.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _Badges(badges: data.badges),
          ),
        if (showsMutual)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _MutualLine(
              friends: data.mutualFriends,
              serverCount: data.mutualServers.length,
              ringColor: backdrop,
            ),
          ),
      ],
    );
  }
}

/// The first few badges, then "+N" for the rest.
class _Badges extends StatelessWidget {
  const _Badges({required this.badges});

  static const _shown = 3;
  static const _size = 22.0;

  final List<ProfileBadge> badges;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final rest = badges.skip(_shown).toList(growable: false);
    Widget tile({required Widget child, String? tooltip, Key? key}) => Tooltip(
      key: key,
      message: tooltip ?? '',
      excludeFromSemantics: tooltip == null,
      child: Container(
        height: _size,
        constraints: const BoxConstraints(minWidth: _size),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: surfaces.quietFill,
          borderRadius: FlucordRadius.full,
        ),
        child: Center(widthFactor: 1, child: child),
      ),
    );
    return Wrap(
      key: const ValueKey('profile-card-badges'),
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final badge in badges.take(_shown))
          tile(
            tooltip: badge.description,
            child: SizedBox.square(
              dimension: 16,
              child: RemoteIdentityImage(
                url: DiscordCdn.badgeIcon(badge.icon),
                fallback: const SizedBox.shrink(),
              ),
            ),
          ),
        if (rest.isNotEmpty)
          tile(
            key: const ValueKey('profile-card-more-badges'),
            tooltip: rest.map((badge) => badge.description).join('\n'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                '+${rest.length}',
                style: FlucordTextRole.caption.style.copyWith(
                  color: surfaces.bodyText,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Up to three mutual friends' faces and the two counts. The host leaves
/// it out when both counts are zero.
class _MutualLine extends StatelessWidget {
  const _MutualLine({
    required this.friends,
    required this.serverCount,
    required this.ringColor,
  });

  static const _face = 16.0;

  final List<ProfileMutualFriend> friends;
  final int serverCount;
  final Color ringColor;

  static String _count(int count, String noun) =>
      '$count mutual $noun${count == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final faces = friends.take(3).toList(growable: false);
    return Row(
      key: const ValueKey('profile-card-mutual'),
      children: [
        if (faces.isNotEmpty) ...[
          OverlappingFaces(
            size: _face,
            ringColor: ringColor,
            faces: [
              for (final face in faces)
                RemoteIdentityImage(
                  url: face.friend.avatarUrl,
                  fallback: ColoredBox(color: surfaces.muted),
                ),
            ],
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            [
              if (friends.isNotEmpty) _count(friends.length, 'friend'),
              if (serverCount > 0) _count(serverCount, 'server'),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlucordTextRole.caption.style.copyWith(
              color: surfaces.muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// The bio, cut after a few lines. A bio that does not fit gets "View full
/// bio", which opens the full profile; a bio that fits has no link.
class _Bio extends StatelessWidget {
  const _Bio({required this.bio, this.onViewFull});

  static const _lines = 3;

  final String bio;
  final VoidCallback? onViewFull;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final style = FlucordTextRole.label.style.copyWith(
      color: surfaces.bodyText,
    );
    final text = Text(
      bio,
      key: const ValueKey('profile-card-bio'),
      maxLines: _lines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final open = onViewFull;
    if (open == null) return text;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured at the card's width and text scale: the same characters
        // fit or not depending on where the lines break.
        final painter = TextPainter(
          text: TextSpan(text: bio, style: style),
          maxLines: _lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final cut = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            text,
            if (cut)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: InkWell(
                  key: const ValueKey('profile-card-view-bio'),
                  onTap: open,
                  borderRadius: FlucordRadius.small,
                  child: Text(
                    'View full bio',
                    style: FlucordTextRole.caption.style.copyWith(
                      color: surfaces.link,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The roles held here as chips with their colour, and "+" for someone who
/// can hand out roles.
class _Roles extends StatelessWidget {
  const _Roles({required this.roles, required this.addable, this.onAdd});

  final List<CommunityRole> roles;
  final List<CommunityRole> addable;
  final ValueChanged<CommunityRole>? onAdd;

  Future<void> _pick(BuildContext context) async {
    final role = await showMenu<CommunityRole>(
      context: context,
      position: menuBelow(context),
      items: [
        if (addable.isEmpty)
          const FlucordMenuItem(label: 'No roles to add', enabled: false),
        for (final role in addable)
          FlucordMenuItem(
            key: ValueKey('profile-card-role-choice-${role.id}'),
            value: role,
            label: role.name,
            leading: _RoleDot(colorValue: role.colorValue),
          ),
      ],
    );
    if (role != null) onAdd?.call(role);
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final add = onAdd;
    return Column(
      key: const ValueKey('profile-card-roles'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Roles',
          style: FlucordTextRole.caption.style.copyWith(color: surfaces.muted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final role in roles)
              Container(
                key: ValueKey('profile-card-role-${role.id}'),
                padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
                decoration: BoxDecoration(
                  color: surfaces.quietFill,
                  borderRadius: FlucordRadius.full,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoleDot(colorValue: role.colorValue),
                    const SizedBox(width: 6),
                    Text(
                      role.name,
                      style: FlucordTextRole.caption.style.copyWith(
                        color: surfaces.bodyText,
                      ),
                    ),
                  ],
                ),
              ),
            if (add != null)
              Builder(
                builder: (context) => FlucordIconButton(
                  key: const ValueKey('profile-card-add-role'),
                  icon: FlucordIcons.add,
                  tooltip: 'Add role',
                  dimension: 20,
                  borderRadius: FlucordRadius.full,
                  onPressed: () => _pick(context),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A role's colour dot. A role with no colour takes the muted grey, which is
/// how Discord draws one.
class _RoleDot extends StatelessWidget {
  const _RoleDot({this.colorValue});

  final int? colorValue;

  @override
  Widget build(BuildContext context) {
    final value = colorValue;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: value == null ? context.surfaces.muted : Color(value),
        shape: BoxShape.circle,
      ),
      child: const SizedBox.square(dimension: 8),
    );
  }
}

/// A profile picture, or [monogram] on [fill] where there is none. The
/// profile card and the profile editor's avatar row both draw it; the caller
/// sizes it and clips it round.
class ProfileAvatarImage extends StatelessWidget {
  const ProfileAvatarImage({
    required this.url,
    required this.monogram,
    this.fill,
    super.key,
  });

  final String? url;
  final String monogram;

  /// The colour behind [monogram]. Null takes the control colour.
  final Color? fill;

  @override
  Widget build(BuildContext context) => RemoteIdentityImage(
    url: url,
    fallback: ColoredBox(
      color: fill ?? context.surfaces.control,
      child: Center(
        child: Text(
          monogram,
          style: FlucordTextRole.display.style.copyWith(
            color: FlucordFixedColors.onFill,
          ),
        ),
      ),
    ),
  );
}
