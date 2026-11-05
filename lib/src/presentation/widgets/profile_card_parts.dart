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
class _Bio extends StatefulWidget {
  const _Bio({required this.bio, this.onViewFull, this.onOpenLink});

  static const _lines = 3;

  final String bio;
  final VoidCallback? onViewFull;
  final ValueChanged<Uri>? onOpenLink;

  @override
  State<_Bio> createState() => _BioState();
}

class _BioState extends State<_Bio> {
  bool _cut = false;

  @override
  Widget build(BuildContext context) {
    final lineHeight = MediaQuery.textScalerOf(
      context,
    ).scale(FlucordTextRole.label.lineHeight);
    final open = widget.onViewFull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeightClamp(
          key: const ValueKey('profile-card-bio'),
          maxHeight: lineHeight * _Bio._lines,
          onCut: (cut) {
            if (mounted && cut != _cut) setState(() => _cut = cut);
          },
          child: ProfileBioText(widget.bio, onOpenLink: widget.onOpenLink),
        ),
        if (_cut && open != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: InkWell(
                key: const ValueKey('profile-card-view-bio'),
                onTap: open,
                borderRadius: FlucordRadius.small,
                child: Text(
                  'View full bio',
                  style: FlucordTextRole.caption.style.copyWith(
                    color: context.surfaces.link,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A bio drawn as chat draws a message: links, markdown, custom emoji,
/// mentions and timestamps. A link goes to [onOpenLink], the card's own link
/// action; without one, links do nothing.
class ProfileBioText extends StatelessWidget {
  const ProfileBioText(this.bio, {this.onOpenLink, super.key});

  final String bio;
  final ValueChanged<Uri>? onOpenLink;

  @override
  Widget build(BuildContext context) => DiscordMarkdown(
    body: bio,
    // Read once, not followed: a bio does not change with the chat.
    workspace: ChatScope.maybeRead(context)?.workspace,
    textStyle: FlucordTextRole.label.style.copyWith(
      color: context.surfaces.bodyText,
    ),
    onTapLink: (href) {
      final uri = Uri.tryParse(href);
      if (uri != null) onOpenLink?.call(uri);
    },
  );
}

/// Shows at most [maxHeight] of [child], clipped, and tells [onCut] after
/// each layout that changes whether [child] is taller. A markdown body has no
/// line count to cut at, so it is cut by height.
class _HeightClamp extends SingleChildRenderObjectWidget {
  const _HeightClamp({
    required this.maxHeight,
    required this.onCut,
    required super.child,
    super.key,
  });

  final double maxHeight;
  final ValueChanged<bool> onCut;

  @override
  _RenderHeightClamp createRenderObject(BuildContext context) =>
      _RenderHeightClamp(maxHeight, onCut);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightClamp renderObject,
  ) {
    renderObject
      ..maxHeight = maxHeight
      ..onCut = onCut;
  }
}

class _RenderHeightClamp extends RenderProxyBox {
  _RenderHeightClamp(this._maxHeight, this.onCut);

  double _maxHeight;
  ValueChanged<bool> onCut;
  bool? _cut;

  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child!;
    child.layout(
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity),
      parentUsesSize: true,
    );
    size = constraints.constrain(
      Size(child.size.width, math.min(child.size.height, _maxHeight)),
    );
    // Half a pixel of slack for rounding in the line heights.
    final cut = child.size.height > _maxHeight + 0.5;
    if (cut == _cut) return;
    _cut = cut;
    SchedulerBinding.instance.addPostFrameCallback((_) => onCut(cut));
  }

  @override
  void paint(PaintingContext context, Offset offset) => context.pushClipRect(
    needsCompositing,
    offset,
    Offset.zero & size,
    super.paint,
  );

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      size.contains(position) && super.hitTest(result, position: position);
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
