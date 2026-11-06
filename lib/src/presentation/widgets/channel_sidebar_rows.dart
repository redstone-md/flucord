part of 'channel_sidebar.dart';

/// The channel list's sizes.
abstract final class _SidebarMetrics {
  static const headerHeight = SidebarRowMetrics.headerHeight;
  static const rowHeight = 30.0;
  static const personRowHeight = SidebarRowMetrics.personRowHeight;
  static const personAvatarSize = SidebarRowMetrics.personAvatarSize;
  static const rowGap = SidebarRowMetrics.rowGap;
  static const listInset = SidebarRowMetrics.listInset;
  static const rowPadding = SidebarRowMetrics.rowPadding;
  static const iconSize = SidebarRowMetrics.iconSize;
  static const iconGap = SidebarRowMetrics.iconGap;

  /// Where a row's name starts, measured from the row's start.
  static const nameStart = rowPadding + iconSize + iconGap;

  /// How much further in a nested row starts.
  static const nestedIndent = 16.0;

  static const labelGapAbove = 16.0;
  static const labelGapBelow = 4.0;
  static const categoryChevronSize = 12.0;

  /// An icon on a group label, and the button around it, kept small so the
  /// label line does not grow.
  static const labelIconSize = 14.0;
  static const labelButtonSize = 18.0;

  /// The button around a [labelIconSize] icon.
  static final labelButtonStyle = IconButton.styleFrom(
    fixedSize: const Size.square(labelButtonSize),
    minimumSize: const Size.square(labelButtonSize),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  /// The DM search in the header.
  static const searchHeight = 28.0;

  static const seatAvatarSize = 20.0;
  static const speakingRingWidth = 2.0;

  /// The unread marker on the sidebar's edge.
  static const unreadMarker = Size(4, 8);
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
        onOpenNotifications?.call(context, menuBelow(context));
      case ServerMenuAction.report:
        onReport?.call();
      case ServerMenuAction.leave:
        onLeave?.call();
      // The header's notification menu has this row already.
      case ServerMenuAction.markRead:
        break;
    }
  }
}

/// The direct-messages block, with its message-request folder.
///
/// The folder is the one piece of state the sidebar keeps: a request row is a
/// question the account has not answered yet, and the answer (both buttons,
/// or opening the conversation) closes it. Swapping the list in place keeps
/// the question and its conversation one gesture apart, the way the official
/// client does.
///
/// The conversations reorder as messages arrive. When the open one moves, the
/// list scrolls just enough to keep it in view.
class _DirectMessagesFolder extends StatefulWidget {
  const _DirectMessagesFolder({
    required this.requests,
    required this.conversations,
    required this.conversationRow,
    required this.requestRows,
    required this.selectedChannelId,
    this.labelTrailing,
  });

  final List<ConversationChannel> requests;

  /// The conversations in the order [ChannelSidebarOrder] gives them.
  final List<ConversationChannel> conversations;
  final Widget Function(ConversationChannel channel) conversationRow;
  final List<Widget> requestRows;
  final String? selectedChannelId;

  /// What sits at the end of the "Direct messages" label, if anything.
  final Widget? labelTrailing;

  @override
  State<_DirectMessagesFolder> createState() => _DirectMessagesFolderState();
}

class _DirectMessagesFolderState extends State<_DirectMessagesFolder> {
  bool _showingRequests = false;

  /// One key per conversation, so a row keeps its element when it moves and
  /// the open one can be found to scroll to.
  final Map<String, GlobalKey> _rowKeys = {};

  @override
  void didUpdateWidget(_DirectMessagesFolder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // With the last request answered the toggle goes, so the folder closes:
    // otherwise nothing would lead back to the conversations.
    if (widget.requests.isEmpty) _showingRequests = false;
    final ids = {for (final channel in widget.conversations) channel.id};
    _rowKeys.removeWhere((id, _) => !ids.contains(id));
    _keepSelectedInView(oldWidget);
  }

  void _keepSelectedInView(_DirectMessagesFolder oldWidget) {
    final selectedId = widget.selectedChannelId;
    if (_showingRequests ||
        selectedId == null ||
        selectedId != oldWidget.selectedChannelId) {
      return;
    }
    int indexIn(List<ConversationChannel> list) =>
        list.indexWhere((channel) => channel.id == selectedId);
    final before = indexIn(oldWidget.conversations);
    final after = indexIn(widget.conversations);
    if (before < 0 || after < 0 || before == after) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _rowKeys[selectedId]?.currentContext;
      if (row == null || !row.mounted) return;
      Scrollable.ensureVisible(
        row,
        alignmentPolicy: after < before
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final requests = widget.requests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(label: 'Direct messages', trailing: widget.labelTrailing),
        if (requests.isNotEmpty)
          _SidebarNavRow(
            key: const ValueKey('message-requests-folder'),
            icon: _showingRequests
                ? FlucordIcons.directMessages
                : FlucordIcons.inbox,
            label: _showingRequests ? 'Back to messages' : 'Message requests',
            trailing: CountBadge(
              key: const ValueKey('message-requests-count'),
              count: requests.length,
            ),
            onPressed: () =>
                setState(() => _showingRequests = !_showingRequests),
          ),
        if (_showingRequests)
          ...widget.requestRows
        else
          for (final channel in widget.conversations)
            KeyedSubtree(
              key: _rowKeys.putIfAbsent(channel.id, GlobalKey.new),
              child: widget.conversationRow(channel),
            ),
      ],
    );
  }
}

/// The DM header's search: a recessed box that opens the dialog to find
/// somebody, or start a conversation with them.
class _DirectMessageSearch extends StatelessWidget {
  const _DirectMessageSearch({required this.onPressed});

  static const _hint = 'Find or start a conversation';

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Semantics(
      button: true,
      label: _hint,
      child: Material(
        color: surfaces.inset,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: surfaces.border),
          borderRadius: FlucordRadius.control,
        ),
        child: InkWell(
          key: const ValueKey('new-direct-message'),
          onTap: onPressed,
          borderRadius: FlucordRadius.control,
          child: ExcludeSemantics(
            child: Container(
              height: _SidebarMetrics.searchHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: _SidebarMetrics.rowPadding,
              ),
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                _hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.label.style.copyWith(
                  color: surfaces.captionText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that opens a place rather than a channel, such as Friends or the
/// message requests: an icon, a label and an optional count at the end.
class _SidebarNavRow extends StatelessWidget {
  const _SidebarNavRow({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.trailing,
    super.key,
  });

  final FlucordIconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final foreground = selected ? surfaces.text : surfaces.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: _SidebarMetrics.rowGap),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? surfaces.quietFill : Colors.transparent,
          borderRadius: FlucordRadius.control,
          child: InkWell(
            onTap: onPressed,
            borderRadius: FlucordRadius.control,
            child: SizedBox(
              height: _SidebarMetrics.rowHeight,
              child: Row(
                children: [
                  const SizedBox(width: _SidebarMetrics.rowPadding),
                  FlucordIcon(
                    icon,
                    size: _SidebarMetrics.iconSize,
                    color: foreground,
                  ),
                  const SizedBox(width: _SidebarMetrics.iconGap),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: FlucordTextRole.label.style.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  ?trailing,
                  const SizedBox(width: _SidebarMetrics.rowPadding),
                ],
              ),
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
    final surfaces = context.surfaces;
    final person = recipient;
    return Padding(
      padding: const EdgeInsets.only(bottom: _SidebarMetrics.rowGap),
      child: Material(
        color: Colors.transparent,
        borderRadius: FlucordRadius.control,
        child: InkWell(
          key: ValueKey('request-${channel.id}'),
          onTap: onPressed,
          borderRadius: FlucordRadius.control,
          child: SizedBox(
            height: _SidebarMetrics.personRowHeight,
            child: Row(
              children: [
                const SizedBox(width: _SidebarMetrics.rowPadding),
                if (person != null)
                  MemberAvatar(
                    member: person,
                    size: _SidebarMetrics.personAvatarSize,
                    presenceBorderColor: surfaces.rail,
                  )
                else
                  SizedBox.square(
                    dimension: _SidebarMetrics.personAvatarSize,
                    child: FlucordIcon(
                      FlucordIcons.person,
                      size: _SidebarMetrics.iconSize,
                      color: surfaces.muted,
                    ),
                  ),
                const SizedBox(width: _SidebarMetrics.iconGap),
                Expanded(
                  child: Text(
                    person?.displayName ?? channel.name,
                    overflow: TextOverflow.ellipsis,
                    style: FlucordTextRole.label.style.copyWith(
                      color: surfaces.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (onAccept != null)
                  FlucordIconButton(
                    key: ValueKey('accept-request-${channel.id}'),
                    tooltip: 'Accept',
                    onPressed: onAccept,
                    icon: FlucordIcons.check,
                  ),
                if (onDecline != null)
                  FlucordIconButton(
                    key: ValueKey('decline-request-${channel.id}'),
                    tooltip: 'Decline',
                    onPressed: onDecline,
                    icon: FlucordIcons.clear,
                  ),
                const SizedBox(width: _SidebarMetrics.rowPadding / 2),
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

/// A group heading with no toggle, such as "Text channels", with room for a
/// small control at its end.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _SidebarMetrics.rowPadding,
        _SidebarMetrics.labelGapAbove,
        _SidebarMetrics.rowPadding,
        _SidebarMetrics.labelGapBelow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: FlucordTextRole.caption.style.copyWith(
                color: context.surfaces.captionText,
              ),
            ),
          ),
          // The label's own line height, so a control never pushes the rows
          // down.
          if (trailing case final trailing?)
            SizedBox(
              height: FlucordTextRole.caption.lineHeight,
              child: trailing,
            ),
        ],
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
    this.onClose,
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

  /// Closes the DM or leaves the group, from a cross that shows while the
  /// row is hovered or open.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final strong = selected || showsUnread;
    final person = recipient;
    final group = channel.isGroupDirectMessage;
    final height = person == null && !group
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
        color: selected ? surfaces.quietFill : Colors.transparent,
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
              child: WithNameplate(
                nameplate: recipient?.tags.nameplate,
                placement: NameplatePlacement.directMessages,
                selected: selected,
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
                        decorated: true,
                        // The dot is cut out of the rail it sits on.
                        presenceBorderColor: surfaces.rail,
                      )
                    else if (group)
                      GroupDirectMessageAvatar(
                        channel: channel,
                        size: _SidebarMetrics.personAvatarSize,
                      )
                    else
                      FlucordIcon(
                        _iconFor(channel),
                        size: _SidebarMetrics.iconSize,
                        color: foreground,
                      ),
                    const SizedBox(width: _SidebarMetrics.iconGap),
                    Expanded(
                      child: NameplateText(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DisplayName(
                              channel.name,
                              style:
                                  (strong
                                          ? FlucordTextRole.label.strong
                                          : FlucordTextRole.label.style)
                                      .copyWith(color: foreground),
                              nameStyle: person?.tags.nameStyle,
                            ),
                            // What the person is doing, the way the member list
                            // says it. With nothing to say the name sits
                            // centred.
                            if (_activityOf(context, person)
                                case final summary?)
                              ActivitySummaryLine(summary: summary),
                          ],
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
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: _SidebarMetrics.rowGap),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          MotionHoverRegion(
            child: onClose == null
                ? row
                : Stack(
                    children: [
                      row,
                      PositionedDirectional(
                        end: _SidebarMetrics.rowPadding / 2,
                        top: 0,
                        bottom: 0,
                        child: _CloseButton(
                          key: ValueKey('close-direct-message-${channel.id}'),
                          shown: selected,
                          tooltip: channel.isGroupDirectMessage
                              ? 'Leave group'
                              : 'Close DM',
                          onPressed: onClose!,
                        ),
                      ),
                    ],
                  ),
          ),
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

  /// The activity line for a DM's person, or null for a channel or somebody
  /// doing nothing.
  static ActivitySummary? _activityOf(BuildContext context, Member? person) =>
      switch (person) {
        final person? => ActivitySummary.of(
          PresenceScope.memberOf(context, person).presenceDetail?.activities ??
              const [],
        ),
        null => null,
      };

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

/// A DM row's cross. Shows while the row is hovered, or always when [shown].
class _CloseButton extends StatelessWidget {
  const _CloseButton({
    required this.shown,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final bool shown;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!shown && MotionHoverRegion.hoveredOf(context) != true) {
      return const SizedBox.shrink();
    }
    return Center(
      child: IconButton(
        tooltip: tooltip,
        iconSize: _SidebarMetrics.labelIconSize,
        style: _SidebarMetrics.labelButtonStyle,
        icon: FlucordIcon(FlucordIcons.clear, color: context.surfaces.muted),
        onPressed: onPressed,
      ),
    );
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
    this.participantMenu,
    super.key,
  });

  final VoiceParticipantStateEvent state;
  final Member? member;
  final String spaceId;

  /// Whether their voice is arriving right now, which rings the avatar.
  final bool speaking;
  final bool indented;

  /// Opens whoever this row is, on the left button. A row that answers no
  /// button reads as a label.
  final OpenProfileCard? onOpenProfile;

  /// What the right button opens: the participant menu, as on a tile. The
  /// profile, without one.
  final ParticipantMenu? participantMenu;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final name = member?.displayNameFor(spaceId) ?? 'Unknown user';
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
    final menu = participantMenu;
    if (open == null && menu == null) return row;
    void openProfile() => open?.call(state.userId, popupAnchorOf(context));
    // The right button and the menu keys too: a row that ignores them is the
    // one place in the app where they stop working.
    return ContextMenuTarget(
      onOpen: (context, position) => menu == null
          ? openProfile()
          : unawaited(menu.open(context, state.userId, position: position)),
      // The row takes the focus itself while it opens the profile.
      focusable: open == null,
      builder: (_, _) => InkWell(
        onTap: open == null ? null : openProfile,
        borderRadius: FlucordRadius.control,
        child: row,
      ),
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
