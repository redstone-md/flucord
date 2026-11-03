part of 'channel_sidebar.dart';

/// The channel list's sizes, from the FLUCORD-68 design.
abstract final class _SidebarMetrics {
  static const headerHeight = 48.0;
  static const rowHeight = 30.0;

  /// A row that shows a person, such as a direct message: room for the
  /// avatar and an activity line under the name.
  static const personRowHeight = 40.0;
  static const personAvatarSize = 28.0;

  /// The space between rows, so two filled rows never touch.
  static const rowGap = 2.0;

  /// How far the list sits in from the sidebar's edges.
  static const listInset = 8.0;

  /// A row's padding on either side of its content.
  static const rowPadding = 8.0;
  static const iconSize = 16.0;
  static const iconGap = 8.0;

  /// Where a row's name starts, measured from the row's start.
  static const nameStart = rowPadding + iconSize + iconGap;

  /// How much further in a nested row starts.
  static const nestedIndent = 16.0;

  static const labelGapAbove = 16.0;
  static const labelGapBelow = 4.0;
  static const categoryChevronSize = 12.0;

  static const seatAvatarSize = 20.0;
  static const speakingRingWidth = 2.0;

  /// The unread marker on the sidebar's edge.
  static const unreadMarker = Size(4, 8);

  /// The selected row's fill: the text colour, faintly.
  static const selectedAlpha = 0.06;
}

/// A server's sidebar header: its name, and every action on the server in the
/// one menu the name opens, the way Discord's own header works.
///
/// An action that is null is left out of the menu. With none at all the name
/// is plain text, because a menu with nothing in it is a dead control.
class _ServerHeader extends StatelessWidget {
  const _ServerHeader({
    required this.title,
    required this.onOpenSettings,
    required this.onLeave,
    required this.onReport,
    required this.onOpenNotifications,
  });

  final Widget title;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onLeave;
  final VoidCallback? onReport;

  /// Raises the notification menu from the given context, at the position.
  final void Function(BuildContext context, RelativeRect position)?
  onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    final entries = serverMenuItems({
      if (onOpenSettings != null) ServerMenuAction.settings,
      if (onOpenNotifications != null) ServerMenuAction.notifications,
      if (onReport != null) ServerMenuAction.report,
      if (onLeave != null) ServerMenuAction.leave,
    });
    if (entries.isEmpty) return title;
    return PopupMenuButton<ServerMenuAction>(
      key: const ValueKey('space-menu'),
      tooltip: 'Server menu',
      position: PopupMenuPosition.under,
      onSelected: (action) => _perform(context, action),
      itemBuilder: (_) => entries,
      child: SizedBox(
        height: _SidebarMetrics.headerHeight,
        child: Row(
          children: [
            Expanded(child: title),
            FlucordIcon(
              FlucordIcons.chevronDown,
              size: _SidebarMetrics.iconSize,
              color: context.surfaces.muted,
            ),
          ],
        ),
      ),
    );
  }

  void _perform(BuildContext context, ServerMenuAction action) {
    switch (action) {
      case ServerMenuAction.settings:
        onOpenSettings?.call();
      case ServerMenuAction.notifications:
        if (_belowHeader(context) case final position?) {
          onOpenNotifications?.call(context, position);
        }
      case ServerMenuAction.report:
        onReport?.call();
      case ServerMenuAction.leave:
        onLeave?.call();
      // The header's notification menu has this row already.
      case ServerMenuAction.markRead:
        break;
    }
  }

  /// Where a follow-up menu opens: under the header, where this one was.
  RelativeRect? _belowHeader(BuildContext context) {
    final header = context.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (header is! RenderBox || overlay is! RenderBox) return null;
    final corner = header.localToGlobal(
      header.size.bottomLeft(Offset.zero),
      ancestor: overlay,
    );
    return RelativeRect.fromRect(
      corner & Size.zero,
      Offset.zero & overlay.size,
    );
  }
}

/// The direct-messages block, with its message-request folder.
///
/// The folder is the one piece of state the sidebar keeps: a request row is a
/// question the account has not answered yet, and the answer (both buttons,
/// or opening the conversation) closes it. Swapping the list in place keeps
/// the question and its conversation one gesture apart, the way the official
/// client does.
class _DirectMessagesFolder extends StatefulWidget {
  const _DirectMessagesFolder({
    required this.requests,
    required this.conversationRows,
    required this.requestRows,
  });

  final List<ConversationChannel> requests;
  final List<Widget> conversationRows;
  final List<Widget> requestRows;

  @override
  State<_DirectMessagesFolder> createState() => _DirectMessagesFolderState();
}

class _DirectMessagesFolderState extends State<_DirectMessagesFolder> {
  bool _showingRequests = false;

  @override
  Widget build(BuildContext context) {
    final requests = widget.requests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel(label: 'Messages'),
        if (requests.isNotEmpty) ...[
          _FolderRow(
            key: const ValueKey('message-requests-folder'),
            label: _showingRequests ? 'Back to messages' : 'Message requests',
            count: requests.length,
            open: _showingRequests,
            onPressed: () =>
                setState(() => _showingRequests = !_showingRequests),
          ),
          const SizedBox(height: 4),
        ],
        ...(_showingRequests ? widget.requestRows : widget.conversationRows),
      ],
    );
  }
}

/// The row that opens and closes the request folder.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.label,
    required this.count,
    required this.open,
    required this.onPressed,
    super.key,
  });

  final String label;
  final int count;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: FlucordRadius.small,
        child: InkWell(
          onTap: onPressed,
          borderRadius: FlucordRadius.small,
          child: SizedBox(
            height: 34,
            child: Row(
              children: [
                const SizedBox(width: 10),
                Icon(
                  open ? Icons.expand_less : Icons.inbox_outlined,
                  size: 17,
                  color: context.surfaces.muted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: FlucordType.label,
                    ),
                  ),
                ),
                CountBadge(
                  key: const ValueKey('message-requests-count'),
                  count: count,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One unanswered message request, with the two answers beside it.
class _MessageRequestRow extends StatelessWidget {
  const _MessageRequestRow({
    required this.channel,
    required this.onPressed,
    this.recipient,
    this.onAccept,
    this.onDecline,
  });

  final ConversationChannel channel;
  final VoidCallback onPressed;
  final Member? recipient;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: FlucordRadius.small,
        child: InkWell(
          key: ValueKey('request-${channel.id}'),
          onTap: onPressed,
          borderRadius: FlucordRadius.small,
          child: SizedBox(
            height: 34,
            child: Row(
              children: [
                const SizedBox(width: 10),
                if (recipient != null)
                  MemberAvatar(member: recipient!, size: 24)
                else
                  Icon(
                    Icons.person_outline,
                    size: 17,
                    color: context.surfaces.muted,
                  ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    recipient?.displayName ?? channel.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: FlucordType.label),
                  ),
                ),
                if (onAccept != null)
                  IconButton(
                    key: ValueKey('accept-request-${channel.id}'),
                    tooltip: 'Accept',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: onAccept,
                    icon: const Icon(Icons.check),
                  ),
                if (onDecline != null)
                  IconButton(
                    key: ValueKey('decline-request-${channel.id}'),
                    tooltip: 'Decline',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: onDecline,
                    icon: const Icon(Icons.close),
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.collapsed,
    required this.onToggle,
    required this.children,
  });

  final ChannelCategory category;
  final bool collapsed;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final color = context.surfaces.captionText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: _SidebarMetrics.labelGapAbove,
            bottom: _SidebarMetrics.labelGapBelow,
          ),
          child: Semantics(
            container: true,
            // The name as written. Capitals are only how it is drawn, and
            // some screen readers would spell them out.
            label: category.name,
            button: true,
            expanded: !collapsed,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('category-${category.id}'),
                onTap: onToggle,
                borderRadius: FlucordRadius.small,
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _SidebarMetrics.rowPadding,
                    ),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            category.name.toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            style: FlucordTextRole.caption.style.copyWith(
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        FlucordIcon(
                          collapsed
                              ? FlucordIcons.chevronRight
                              : FlucordIcons.chevronDown,
                          size: _SidebarMetrics.categoryChevronSize,
                          color: color,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// A group heading with no toggle, such as "Text channels".
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _SidebarMetrics.rowPadding,
        _SidebarMetrics.labelGapAbove,
        _SidebarMetrics.rowPadding,
        _SidebarMetrics.labelGapBelow,
      ),
      child: Text(
        label,
        style: FlucordTextRole.caption.style.copyWith(
          color: context.surfaces.captionText,
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.selected,
    required this.onPressed,
    this.recipient,
    this.indented = false,
    this.muted = false,
    this.showsUnread = false,
    this.notificationLevel = MessageNotificationLevel.allMessages,
    this.onNotificationRequest,
  });

  final ConversationChannel channel;
  final bool selected;
  final VoidCallback onPressed;
  final Member? recipient;
  final bool indented;
  final bool muted;
  final bool showsUnread;
  final MessageNotificationLevel notificationLevel;
  final ValueChanged<NotificationMenuRequest>? onNotificationRequest;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final strong = selected || showsUnread;
    final person = recipient;
    final height = person == null
        ? _SidebarMetrics.rowHeight
        : _SidebarMetrics.personRowHeight;
    // A muted channel reads as quieter than a plain read one, which is how the
    // official client tells the two apart at a glance.
    final foreground = muted && !selected
        ? surfaces.captionText
        : strong
        ? surfaces.text
        : surfaces.muted;
    final row = Semantics(
      container: true,
      label: activityLabel(
        channel.name,
        mentionCount: channel.mentionCount,
        muted: muted,
        unread: showsUnread,
      ),
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? surfaces.text.withValues(alpha: _SidebarMetrics.selectedAlpha)
            : Colors.transparent,
        borderRadius: FlucordRadius.control,
        child: InkWell(
          key: ValueKey('channel-${channel.id}'),
          onTap: onPressed,
          onSecondaryTapDown: onNotificationRequest == null
              ? null
              : (details) => _openMenu(context, details.globalPosition),
          borderRadius: FlucordRadius.control,
          // The label above already says all of this. The badge alone would
          // read as a bare number.
          child: ExcludeSemantics(
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  SizedBox(
                    width: indented
                        ? _SidebarMetrics.rowPadding +
                              _SidebarMetrics.nestedIndent
                        : _SidebarMetrics.rowPadding,
                  ),
                  if (person != null)
                    MemberAvatar(
                      member: person,
                      size: _SidebarMetrics.personAvatarSize,
                      // The dot is cut out of the rail it sits on.
                      presenceBorderColor: surfaces.rail,
                    )
                  else
                    FlucordIcon(
                      _iconFor(channel),
                      size: _SidebarMetrics.iconSize,
                      color: foreground,
                    ),
                  const SizedBox(width: _SidebarMetrics.iconGap),
                  Expanded(
                    child: Text(
                      channel.name,
                      overflow: TextOverflow.ellipsis,
                      style: FlucordTextRole.label.style.copyWith(
                        color: foreground,
                        fontWeight: strong ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (muted)
                    Padding(
                      key: ValueKey('channel-muted-${channel.id}'),
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: FlucordIcon(
                        FlucordIcons.silent,
                        size: _SidebarMetrics.iconSize,
                        color: foreground,
                      ),
                    ),
                  if (channel.mentionCount > 0)
                    CountBadge(
                      key: ValueKey('channel-mention-${channel.id}'),
                      count: channel.mentionCount,
                    ),
                  const SizedBox(width: _SidebarMetrics.rowPadding),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: _SidebarMetrics.rowGap),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          row,
          // The selected row is read the moment it opens, so only the others
          // carry the marker.
          if (showsUnread && !selected)
            PositionedDirectional(
              start: -_SidebarMetrics.listInset,
              top: (height - _SidebarMetrics.unreadMarker.height) / 2,
              child: _UnreadMarker(
                key: ValueKey('channel-unread-${channel.id}'),
              ),
            ),
        ],
      ),
    );
  }

  static FlucordIconData _iconFor(ConversationChannel channel) {
    if (channel.isDirectMessage) return FlucordIcons.person;
    if (channel.isThread) return FlucordIcons.threads;
    return switch (channel.kind) {
      ChannelKind.text => FlucordIcons.textChannel,
      ChannelKind.voice => FlucordIcons.voiceChannel,
      ChannelKind.forum => FlucordIcons.forum,
      ChannelKind.media => FlucordIcons.image,
    };
  }

  Future<void> _openMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final request = await showNotificationSettingsMenu(
      context: context,
      position: RelativeRect.fromRect(
        overlay.globalToLocal(position) & Size.zero,
        Offset.zero & overlay.size,
      ),
      muted: muted,
      level: notificationLevel,
      isSpaceScope: false,
    );
    if (request != null) onNotificationRequest?.call(request);
  }
}

/// The small bar on the sidebar's edge that marks an unread channel.
class _UnreadMarker extends StatelessWidget {
  const _UnreadMarker({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: _SidebarMetrics.unreadMarker.width,
    height: _SidebarMetrics.unreadMarker.height,
    decoration: BoxDecoration(
      color: context.surfaces.text,
      // Flat against the edge, round on the side facing the row.
      borderRadius: BorderRadiusDirectional.horizontal(
        end: FlucordRadius.small.topRight,
      ),
    ),
  );
}

/// One person seated in a voice channel, shown under its sidebar row.
///
/// Discord puts the occupants directly beneath the channel, and that placement
/// is the whole point: it answers "is anyone in there" before the user commits
/// to joining. A member this client has never loaded still gets a row — the
/// voice state proves they are there, and hiding them would under-report the
/// room.
class VoiceSeatRow extends StatelessWidget {
  const VoiceSeatRow({
    required this.state,
    required this.member,
    required this.spaceId,
    this.speaking = false,
    this.indented = false,
    this.onOpenProfile,
    super.key,
  });

  final VoiceParticipantStateEvent state;
  final Member? member;
  final String spaceId;

  /// Whether their voice is arriving right now, which rings the avatar.
  final bool speaking;
  final bool indented;

  /// Opens whoever this row is. Discord opens a profile from these rows with
  /// either button, and a row that answers neither reads as a label.
  final void Function(String userId)? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final name = member?.displayName ?? 'Unknown user';
    final silenced = state.selfMuted || state.serverMuted;
    final deafened = state.selfDeafened || state.serverDeafened;
    final nameColor = speaking
        ? surfaces.text
        : silenced || deafened
        ? surfaces.captionText
        : surfaces.muted;
    final row = SizedBox(
      height: _SidebarMetrics.rowHeight,
      child: Padding(
        // The avatar lines up with the channel's name above it.
        padding: EdgeInsetsDirectional.only(
          start:
              _SidebarMetrics.nameStart +
              (indented ? _SidebarMetrics.nestedIndent : 0),
          end: _SidebarMetrics.rowPadding,
        ),
        child: Row(
          children: [
            _SeatAvatar(
              userId: state.userId,
              member: member,
              spaceId: spaceId,
              speaking: speaking,
            ),
            const SizedBox(width: _SidebarMetrics.iconGap),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.label.style.copyWith(color: nameColor),
              ),
            ),
            if (state.isStreaming)
              const _SeatStateIcon(FlucordIcons.screenShare),
            if (state.isVideoEnabled) const _SeatStateIcon(FlucordIcons.camera),
            if (deafened)
              const _SeatStateIcon(FlucordIcons.headphonesOff)
            else if (silenced)
              const _SeatStateIcon(FlucordIcons.micOff),
          ],
        ),
      ),
    );
    final open = onOpenProfile;
    if (open == null) return row;
    return InkWell(
      onTap: () => open(state.userId),
      // The right button too: Discord opens the same card from it, and a row
      // that ignores it is the one place in the app where the mouse stops
      // working.
      onSecondaryTap: () => open(state.userId),
      borderRadius: FlucordRadius.control,
      child: row,
    );
  }
}

/// A seat's avatar, with the speaking ring drawn around it. The ring sits
/// outside the avatar's box, so the row does not move when it comes and goes.
class _SeatAvatar extends StatelessWidget {
  const _SeatAvatar({
    required this.userId,
    required this.member,
    required this.spaceId,
    required this.speaking,
  });

  final String userId;
  final Member? member;
  final String spaceId;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    const ring = _SidebarMetrics.speakingRingWidth;
    return SizedBox.square(
      key: ValueKey('voice-seat-avatar-$userId'),
      dimension: _SidebarMetrics.seatAvatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: switch (member) {
              final resolved? => MemberAvatar(
                member: resolved,
                size: _SidebarMetrics.seatAvatarSize,
                spaceId: spaceId,
                // The ring is this row's signal; a presence dot would crowd it.
                showPresence: false,
              ),
              null => FlucordIcon(
                FlucordIcons.person,
                size: _SidebarMetrics.iconSize,
                color: context.surfaces.muted,
              ),
            },
          ),
          if (speaking)
            Positioned.fill(
              left: -ring,
              top: -ring,
              right: -ring,
              bottom: -ring,
              child: Container(
                key: ValueKey('voice-seat-ring-$userId'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.surfaces.success,
                    width: ring,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small state mark at the end of a seat: muted, deafened, video, stream.
class _SeatStateIcon extends StatelessWidget {
  const _SeatStateIcon(this.icon);

  final FlucordIconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 4),
    child: FlucordIcon(
      icon,
      size: _SidebarMetrics.iconSize,
      color: context.surfaces.muted,
    ),
  );
}
