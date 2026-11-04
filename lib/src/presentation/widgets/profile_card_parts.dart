part of 'profile_card.dart';

/// The name, then the username line, the badges and, where [metrics] show
/// it, the mutual line.
class _Names extends StatelessWidget {
  const _Names({
    required this.data,
    required this.metrics,
    required this.backdrop,
    this.onOpenFullProfile,
  });

  final ProfileCardData data;
  final _ProfileMetrics metrics;

  /// The colour the names sit on, which rings the mutual friends' faces.
  final Color backdrop;

  /// A click on the name calls it.
  final VoidCallback? onOpenFullProfile;

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
      style: metrics.name.style.copyWith(color: surfaces.text),
      nameStyle: data.nameStyle,
    );
    final showsMutual =
        metrics.showsMutualLine &&
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
