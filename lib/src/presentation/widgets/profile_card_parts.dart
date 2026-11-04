part of 'profile_card.dart';

/// The name, then the username line, the badges and the mutual line.
class _Names extends StatelessWidget {
  const _Names({required this.data});

  final ProfileCardData data;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final handle = [
      ?data.username,
      if (data.pronouns.isNotEmpty) data.pronouns,
    ].join(' · ');
    final clan = data.clanTag;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: FlucordTextRole.title.style.copyWith(color: surfaces.text),
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
        if (data.mutualFriends.isNotEmpty || data.mutualServerCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _MutualLine(
              friends: data.mutualFriends,
              serverCount: data.mutualServerCount,
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
          borderRadius: FlucordRadius.small,
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
                url: badge.icon.isEmpty
                    ? null
                    : 'https://cdn.discordapp.com/badge-icons/${badge.icon}.png',
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
  const _MutualLine({required this.friends, required this.serverCount});

  static const _face = 16.0;
  static const _overlap = 4.0;
  static const _ring = 2.0;

  final List<MutualFriend> friends;
  final int serverCount;

  static String _count(int count, String noun) =>
      '$count mutual $noun${count == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final faces = friends.take(3).toList(growable: false);
    final outer = _face + 2 * _ring;
    return Row(
      key: const ValueKey('profile-card-mutual'),
      children: [
        if (faces.isNotEmpty) ...[
          SizedBox(
            width: outer + (faces.length - 1) * (outer - _overlap - _ring),
            height: outer,
            child: Stack(
              children: [
                for (var index = 0; index < faces.length; index++)
                  Positioned(
                    left: index * (outer - _overlap - _ring),
                    child: Container(
                      width: outer,
                      height: outer,
                      padding: const EdgeInsets.all(_ring),
                      decoration: BoxDecoration(
                        color: surfaces.raised,
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: RemoteIdentityImage(
                          url: faces[index].avatarUrl,
                          fallback: ColoredBox(color: surfaces.muted),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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

/// The bio, cut after a few lines with "View full bio" to open the rest.
class _Bio extends StatefulWidget {
  const _Bio({required this.bio});

  static const _lines = 3;

  final String bio;

  @override
  State<_Bio> createState() => _BioState();
}

class _BioState extends State<_Bio> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final style = FlucordTextRole.label.style.copyWith(
      color: surfaces.bodyText,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.bio, style: style),
          maxLines: _Bio._lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final cut = !_expanded && painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.bio,
              key: const ValueKey('profile-card-bio'),
              maxLines: _expanded ? null : _Bio._lines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: style,
            ),
            if (cut)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: InkWell(
                  key: const ValueKey('profile-card-view-bio'),
                  onTap: () => setState(() => _expanded = true),
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
      position: _menuBelow(context),
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
                  borderRadius: FlucordRadius.small,
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
                builder: (context) => Tooltip(
                  message: 'Add role',
                  child: InkWell(
                    key: const ValueKey('profile-card-add-role'),
                    onTap: () => _pick(context),
                    borderRadius: FlucordRadius.small,
                    child: SizedBox.square(
                      dimension: 20,
                      child: Center(
                        child: FlucordIcon(
                          FlucordIcons.add,
                          size: 14,
                          color: surfaces.muted,
                        ),
                      ),
                    ),
                  ),
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
