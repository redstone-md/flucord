part of 'channel_sidebar.dart';

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
                  Container(
                    key: ValueKey('channel-mention-${channel.id}'),
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FlucordColors.mention,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${channel.mentionCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
