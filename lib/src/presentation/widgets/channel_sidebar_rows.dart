part of 'channel_sidebar.dart';

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
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(5),
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
                      fontSize: 13,
                    ),
                  ),
                ),
                MentionBadge(
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
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          key: ValueKey('request-${channel.id}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(5),
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
                    style: const TextStyle(fontSize: 13),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('category-${category.id}'),
            onTap: onToggle,
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 28,
              child: Row(
                children: [
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 16,
                    color: context.surfaces.muted,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      category.name.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ...children,
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 8, 6),
      child: Text(
        label,
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
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
    // A muted channel reads as quieter than a plain read one, which is how the
    // official client tells the two apart at a glance.
    final foreground = muted && !selected
        ? context.surfaces.muted.withValues(alpha: 0.6)
        : selected
        ? Theme.of(context).colorScheme.onSurface
        : showsUnread
        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.88)
        : context.surfaces.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? context.surfaces.raised : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          key: ValueKey('channel-${channel.id}'),
          onTap: onPressed,
          onSecondaryTapDown: onNotificationRequest == null
              ? null
              : (details) => _openMenu(context, details.globalPosition),
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 34,
            child: Row(
              children: [
                SizedBox(width: indented ? 18 : 10),
                if (recipient != null)
                  MemberAvatar(member: recipient!, size: 24)
                else
                  Icon(
                    channel.isDirectMessage
                        ? Icons.person_outline
                        : channel.isThread
                        ? Icons.forum_outlined
                        : switch (channel.kind) {
                            ChannelKind.text => Icons.tag,
                            ChannelKind.voice => Icons.volume_up_outlined,
                            ChannelKind.forum => Icons.forum_outlined,
                            ChannelKind.media => Icons.perm_media_outlined,
                          },
                    size: 17,
                    color: foreground,
                  ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    channel.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13,
                      fontWeight: showsUnread || selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (muted)
                  Padding(
                    key: ValueKey('channel-muted-${channel.id}'),
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      size: 14,
                      color: foreground,
                    ),
                  ),
                if (channel.mentionCount > 0)
                  MentionBadge(
                    key: ValueKey('channel-mention-${channel.id}'),
                    count: channel.mentionCount,
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final request = await showNotificationSettingsMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      muted: muted,
      level: notificationLevel,
      isSpaceScope: false,
    );
    if (request != null) onNotificationRequest?.call(request);
  }
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
    this.indented = false,
    this.onOpenProfile,
    super.key,
  });

  final VoiceParticipantStateEvent state;
  final Member? member;
  final String spaceId;
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
    final row = Padding(
      padding: EdgeInsets.fromLTRB(indented ? 34 : 22, 1, 8, 1),
      child: Row(
        children: [
          if (member case final resolved?)
            MemberAvatar(member: resolved, size: 18, spaceId: spaceId)
          else
            Icon(Icons.person_outline, size: 16, color: surfaces.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: silenced || deafened
                    ? surfaces.muted
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (state.isStreaming)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.screen_share_outlined,
                size: 13,
                color: surfaces.muted,
              ),
            ),
          if (state.isVideoEnabled)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.videocam_outlined,
                size: 13,
                color: surfaces.muted,
              ),
            ),
          if (deafened)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.headset_off_outlined,
                size: 13,
                color: surfaces.muted,
              ),
            )
          else if (silenced)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.mic_off_outlined,
                size: 13,
                color: surfaces.muted,
              ),
            ),
        ],
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
      child: row,
    );
  }
}
