part of 'profile_card.dart';

/// Opens the full profile window [builder] makes over the app, and completes
/// when it closes. Escape or a click outside closes it; [builder] gets a
/// callback that does the same, for an action that leaves the window.
Future<void> showFullProfile({
  required BuildContext context,
  required Widget Function(VoidCallback close) builder,
}) => showDialog<void>(
  context: context,
  builder: (context) {
    final route = ModalRoute.of(context)!;
    // Closes the window even with a card or a menu it opened on top.
    void close() {
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else if (route.isActive) {
        route.navigator!.removeRoute(route);
      }
    }

    return builder(close);
  },
);

/// The full profile: one person's card on the left, with everything the
/// popout card leaves out, and their activity and mutuals in tabs on the
/// right. Discord's full profile is the model.
///
/// The window does not scroll. The card's content scrolls inside the card,
/// and the right column scrolls on its own. Parts with no data hide.
class FullProfile extends StatelessWidget {
  const FullProfile({
    required this.data,
    this.actions = const ProfileCardActions(),
    this.note,
    this.now,
    super.key,
  });

  static const _maxWidth = 880.0;
  static const _maxHeight = 720.0;
  static const _cardWidth = 340.0;

  /// The card's distance from the window's top and left edges. With the
  /// card's [FlucordRadius.overlay] it makes the window's 24.
  static const _cardInset = 8.0;

  final ProfileCardData data;
  final ProfileCardActions actions;

  /// The private note, under everything else in the card. Null where the
  /// host keeps no notes.
  final Widget? note;

  /// The moment the activity's elapsed time is measured against.
  final DateTime? now;

  @override
  Widget build(BuildContext context) => FlucordDialog.frame(
    large: true,
    maxWidth: _maxWidth,
    maxHeight: _maxHeight,
    child: MotionHoverRegion(
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: '${data.displayName} profile',
        child: SizedBox.expand(
          key: const ValueKey('full-profile'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: _cardInset,
                  top: _cardInset,
                ),
                child: SizedBox(
                  width: _cardWidth,
                  child: ProfileTheme(
                    colors: data.themeColors,
                    child: _FullProfileCard(
                      data: data,
                      actions: actions,
                      note: note,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _FullProfileSide(
                  data: data,
                  actions: actions,
                  now: now ?? DateTime.now(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The window's left column: the card on the inset colour, rounded at the
/// top only and running to the window's bottom edge. Its content scrolls
/// inside it.
class _FullProfileCard extends StatelessWidget {
  const _FullProfileCard({
    required this.data,
    required this.actions,
    required this.note,
  });

  static const _metrics = _ProfileMetrics.window;

  final ProfileCardData data;
  final ProfileCardActions actions;
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final roles = data.roles;
    final showsRoles =
        roles != null && (roles.isNotEmpty || actions.onAddRole != null);
    final memberSince = data.memberSince;
    final friendsSince = data.friendsSince;
    return ClipRRect(
      key: const ValueKey('full-profile-card'),
      borderRadius: const BorderRadius.vertical(
        top: FlucordRadius.overlayCorner,
      ),
      child: ProfileBackdrop(
        key: const ValueKey('full-profile-theme'),
        color: surfaces.inset,
        colors: data.themeColors,
        child: _EffectBox(
          data: data,
          child: SingleChildScrollView(
            key: const ValueKey('full-profile-card-scroll'),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    data: data,
                    metrics: _metrics,
                    backdrop: surfaces.inset,
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      _metrics.padding,
                      12,
                      _metrics.padding,
                      _metrics.padding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 16,
                      children: [
                        _Names(
                          data: data,
                          metrics: _metrics,
                          backdrop: surfaces.inset,
                        ),
                        ?_FullProfileButtons.of(actions),
                        if (data.bio.isNotEmpty)
                          ProfileBioText(
                            data.bio,
                            key: const ValueKey('full-profile-bio'),
                            onOpenLink: actions.onOpenLink,
                          ),
                        if (memberSince != null)
                          _AboutSection(
                            key: const ValueKey('full-profile-member-since'),
                            heading: 'Member since',
                            child: _AboutText(
                              [
                                'Discord ${_date(context, memberSince)}',
                                if (data.serverSince case final server?)
                                  '${server.serverName} '
                                      '${_date(context, server.since)}',
                              ].join(' · '),
                            ),
                          ),
                        if (friendsSince != null)
                          _AboutSection(
                            key: const ValueKey('full-profile-friends-since'),
                            heading: 'Friends since',
                            child: _AboutText(_date(context, friendsSince)),
                          ),
                        if (data.connections.isNotEmpty)
                          _AboutSection(
                            key: const ValueKey('full-profile-connections'),
                            heading: 'Connections',
                            child: _Connections(
                              connections: data.connections,
                              onOpen: actions.onOpenLink,
                            ),
                          ),
                        if (showsRoles)
                          _Roles(
                            roles: roles,
                            addable: actions.addableRoles,
                            onAdd: actions.onAddRole,
                            removable: actions.removableRoleIds,
                            onRemove: actions.onRemoveRole,
                            folds: false,
                          ),
                        if (note case final note?)
                          _AboutSection(
                            heading: 'Note (only you see it)',
                            child: note,
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
    );
  }
}

/// Message, add friend and "more", under the names. Null when the host
/// offers none of them.
class _FullProfileButtons extends StatelessWidget {
  const _FullProfileButtons._(this.actions);

  static _FullProfileButtons? of(ProfileCardActions actions) =>
      actions.onMessage == null &&
          actions.onAddFriend == null &&
          actions.menu.isEmpty
      ? null
      : _FullProfileButtons._(actions);

  final ProfileCardActions actions;

  @override
  Widget build(BuildContext context) {
    final fill = context.surfaces.control;
    final message = actions.onMessage;
    final addFriend = actions.onAddFriend;
    final menu = actions.menu;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (message != null)
          FlucordButton(
            key: const ValueKey('full-profile-message'),
            label: 'Message',
            kind: FlucordButtonKind.primary,
            onPressed: () => message(''),
          ),
        if (addFriend != null)
          FlucordIconButton(
            key: const ValueKey('full-profile-add-friend'),
            icon: FlucordIcons.addFriend,
            tooltip: 'Add friend',
            fill: fill,
            dimension: 32,
            onPressed: addFriend,
          ),
        if (menu.isNotEmpty)
          Builder(
            builder: (context) => FlucordIconButton(
              key: const ValueKey('full-profile-more'),
              icon: FlucordIcons.more,
              tooltip: 'More',
              fill: fill,
              dimension: 32,
              onPressed: () => _openMenu(context, menu),
            ),
          ),
      ],
    );
  }
}

/// One row per linked account. A row whose service has a public page opens
/// it; the others only name the account.
class _Connections extends StatelessWidget {
  const _Connections({required this.connections, required this.onOpen});

  final List<ProfileConnection> connections;
  final ValueChanged<Uri>? onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      for (final connection in connections)
        _ConnectionRow(
          connection: connection,
          onOpen: switch ((connection.link, onOpen)) {
            (final link?, final open?) => () => open(link),
            _ => null,
          },
        ),
    ],
  );
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.connection, required this.onOpen});

  final ProfileConnection connection;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final service = connection.serviceName;
    final open = onOpen;
    return Material(
      key: ValueKey('profile-connection-${connection.type}'),
      color: surfaces.raised,
      shape: RoundedRectangleBorder(
        borderRadius: FlucordRadius.medium,
        side: BorderSide(color: surfaces.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ServiceLogo(connection.type, size: 20, color: surfaces.text),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  connection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  semanticsLabel: '$service: ${connection.name}',
                  style: FlucordTextRole.label.strong.copyWith(
                    color: surfaces.text,
                  ),
                ),
              ),
              if (connection.verified) ...[
                const SizedBox(width: 8),
                FlucordIcon(
                  FlucordIcons.verified,
                  size: 14,
                  color: surfaces.success,
                ),
              ],
              if (open != null) ...[
                const SizedBox(width: 8),
                FlucordIcon(
                  FlucordIcons.openExternal,
                  size: 14,
                  color: surfaces.muted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
