part of 'profile_card.dart';

enum _FullProfileTab { activity, friends, servers }

/// The window's right column: the tabs, then the chosen tab's content, which
/// scrolls on its own. A tab with nobody in it is not offered.
class _FullProfileSide extends StatefulWidget {
  const _FullProfileSide({
    required this.data,
    required this.actions,
    required this.now,
  });

  final ProfileCardData data;
  final ProfileCardActions actions;
  final DateTime now;

  @override
  State<_FullProfileSide> createState() => _FullProfileSideState();
}

class _FullProfileSideState extends State<_FullProfileSide> {
  var _chosen = _FullProfileTab.activity;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final data = widget.data;
    final friends = data.mutualFriends.length;
    final servers = data.mutualServers.length;
    final tabs = {
      _FullProfileTab.activity: 'Activity',
      if (friends > 0)
        _FullProfileTab.friends:
            '$friends Mutual friend${friends == 1 ? '' : 's'}',
      if (servers > 0)
        _FullProfileTab.servers:
            '$servers Mutual server${servers == 1 ? '' : 's'}',
    };
    // A tab whose people went away while it was open falls back to Activity.
    final shown = tabs.containsKey(_chosen)
        ? _chosen
        : _FullProfileTab.activity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Container(
            padding: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: surfaces.border)),
            ),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final MapEntry(key: tab, value: label) in tabs.entries)
                  FlucordTab(
                    key: ValueKey('full-profile-tab-${tab.name}'),
                    label: label,
                    selected: tab == shown,
                    onPressed: () => setState(() => _chosen = tab),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('full-profile-side-scroll'),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: switch (shown) {
              _FullProfileTab.activity => _ActivityTab(
                data: data,
                onJoin: widget.actions.onJoinVoice,
                now: widget.now,
              ),
              _FullProfileTab.friends => _MutualFriendRows(
                friends: data.mutualFriends,
                onOpen: widget.actions.onOpenProfile,
              ),
              _FullProfileTab.servers => _MutualServerRows(
                servers: data.mutualServers,
                onOpen: widget.actions.onOpenServer,
              ),
            },
          ),
        ),
      ],
    );
  }
}

/// What the person is doing now and the voice channel they sit in, or one
/// quiet line when there is neither.
class _ActivityTab extends StatelessWidget {
  const _ActivityTab({
    required this.data,
    required this.onJoin,
    required this.now,
  });

  final ProfileCardData data;
  final ValueChanged<String>? onJoin;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final activity = data.activity;
    final room = data.voiceRoom;
    if (activity == null && room == null) {
      return Text(
        'Nothing going on right now.',
        key: const ValueKey('full-profile-no-activity'),
        style: FlucordTextRole.label.style.copyWith(color: surfaces.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Current activity',
          style: FlucordTextRole.caption.style.copyWith(
            color: surfaces.captionText,
          ),
        ),
        if (activity != null) ...[
          const SizedBox(height: 8),
          ActivityCard(
            activity: activity,
            now: now,
            artSize: ActivityFrame.windowArt,
          ),
        ],
        if (room != null) ...[
          const SizedBox(height: 8),
          VoiceRoomCard(
            room: room,
            artSize: ActivityFrame.windowArt,
            onJoin: switch (onJoin) {
              final join? => () => join(room.channel.id),
              null => null,
            },
          ),
        ],
      ],
    );
  }
}

/// One row per mutual friend: their face with the status dot, their name,
/// and what they are doing or their status. A click opens their card.
class _MutualFriendRows extends StatelessWidget {
  const _MutualFriendRows({required this.friends, required this.onOpen});

  static const _face = 32.0;

  final List<ProfileMutualFriend> friends;
  final OpenProfileCard? onOpen;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (:friend, :presence) in friends)
          Builder(
            builder: (rowContext) => _SideRow(
              key: ValueKey('full-profile-friend-${friend.id}'),
              onTap: switch (onOpen) {
                final open? => () => open(friend.id, popupAnchorOf(rowContext)),
                null => null,
              },
              leading: SizedBox.square(
                dimension: _face,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: ClipOval(
                        child: RemoteIdentityImage(
                          url: friend.avatarUrl,
                          fallback: ColoredBox(
                            color: surfaces.control,
                            child: Center(
                              child: Text(
                                monogramOf(friend.displayName),
                                style: FlucordTextRole.caption.strong.copyWith(
                                  color: FlucordFixedColors.onFill,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (presence != null)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: PresenceIndicator(
                          presence: presence,
                          size: 14,
                          borderColor: surfaces.raised,
                        ),
                      ),
                  ],
                ),
              ),
              title: friend.displayName,
              subtitle: switch (presence) {
                null => null,
                final presence => switch (ActivitySummary.of(
                  presence.activities,
                )) {
                  final summary? => ActivitySummaryLine(summary: summary),
                  null => _SideCaption(presence.status.label),
                },
              },
            ),
          ),
      ],
    );
  }
}

/// One row per mutual server: its tile, its name, and what the person is
/// called there. A click opens the server.
class _MutualServerRows extends StatelessWidget {
  const _MutualServerRows({required this.servers, required this.onOpen});

  final List<ProfileMutualServer> servers;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (:space, :nickname) in servers)
        _SideRow(
          key: ValueKey('full-profile-server-${space.id}'),
          onTap: switch (onOpen) {
            final open? => () => open(space.id),
            null => null,
          },
          leading: ArtTile(
            url: space.iconUrl,
            monogram: space.monogram,
            color: Color(space.colorValue),
            size: 32,
          ),
          title: space.name,
          subtitle: nickname == null ? null : _SideCaption(nickname),
        ),
    ],
  );
}

/// A row in the right column: [leading], then [title] over [subtitle].
class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final Widget leading;
  final String title;
  final Widget? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return InkWell(
      onTap: onTap,
      borderRadius: FlucordRadius.medium,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlucordTextRole.label.strong.copyWith(
                      color: context.surfaces.text,
                    ),
                  ),
                  ?subtitle,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideCaption extends StatelessWidget {
  const _SideCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: FlucordTextRole.caption.style.copyWith(
      color: context.surfaces.muted,
    ),
  );
}
