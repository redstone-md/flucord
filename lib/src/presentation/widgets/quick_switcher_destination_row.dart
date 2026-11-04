part of 'quick_switcher.dart';

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.destination,
    required this.selected,
    required this.onHover,
    required this.onPressed,
    super.key,
  });

  final QuickSwitcherDestination destination;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final metadata = selected
        ? Colors.white.withValues(alpha: 0.72)
        : context.surfaces.muted;
    final activity = [
      if (destination.unread) 'unread',
      if (destination.mentionCount > 0) '${destination.mentionCount} mentions',
    ].join(', ');
    return Semantics(
      label: [
        destination.path,
        _kindName(destination.kind),
        if (activity.isNotEmpty) activity,
      ].join(', '),
      button: true,
      selected: selected,
      onTap: onPressed,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => onHover(),
        child: Material(
          color: selected ? context.surfaces.brand : Colors.transparent,
          borderRadius: FlucordRadius.small,
          child: InkWell(
            key: ValueKey('quick-switcher-${destination.key}'),
            onTap: onPressed,
            borderRadius: FlucordRadius.small,
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  FlucordIcon(
                    _kindIcon(destination.kind),
                    size: 18,
                    color: metadata,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          destination.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: FlucordType.label,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _kindName(destination.kind),
                          style: TextStyle(
                            color: metadata,
                            fontSize: FlucordType.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (destination.unread)
                    Container(
                      key: ValueKey('quick-switcher-unread-${destination.key}'),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: foreground,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (destination.mentionCount > 0) ...[
                    const SizedBox(width: 8),
                    CountBadge(count: destination.mentionCount),
                  ],
                  const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickSwitcherFooter extends StatelessWidget {
  const _QuickSwitcherFooter();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: const [
        _KeyboardHint(keys: ['↑', '↓'], label: 'navigate'),
        SizedBox(width: 14),
        _KeyboardHint(keys: ['Enter'], label: 'go'),
        SizedBox(width: 14),
        _KeyboardHint(keys: ['Esc'], label: 'close'),
        SizedBox(width: 12),
      ],
    ),
  );
}

class _KeyboardHint extends StatelessWidget {
  const _KeyboardHint({required this.keys, required this.label});

  final List<String> keys;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final keyLabel in keys) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: context.surfaces.inset,
            borderRadius: FlucordRadius.small,
          ),
          child: Text(
            keyLabel,
            style: TextStyle(
              color: context.surfaces.muted,
              fontSize: FlucordType.caption,
            ),
          ),
        ),
        const SizedBox(width: 3),
      ],
      Text(
        label,
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: FlucordType.caption,
        ),
      ),
    ],
  );
}

String _groupName(QuickSwitcherDestinationKind kind) => switch (kind) {
  QuickSwitcherDestinationKind.guild => 'Servers',
  QuickSwitcherDestinationKind.directMessage => 'Direct Messages',
  QuickSwitcherDestinationKind.textChannel => 'Text Channels',
  QuickSwitcherDestinationKind.voiceChannel => 'Voice Channels',
  QuickSwitcherDestinationKind.forumChannel => 'Forums',
  QuickSwitcherDestinationKind.mediaChannel => 'Media Channels',
  QuickSwitcherDestinationKind.thread => 'Active Threads',
};

String _kindName(QuickSwitcherDestinationKind kind) => switch (kind) {
  QuickSwitcherDestinationKind.guild => 'Server',
  QuickSwitcherDestinationKind.directMessage => 'Direct Message',
  QuickSwitcherDestinationKind.textChannel => 'Text Channel',
  QuickSwitcherDestinationKind.voiceChannel => 'Voice Channel',
  QuickSwitcherDestinationKind.forumChannel => 'Forum',
  QuickSwitcherDestinationKind.mediaChannel => 'Media Channel',
  QuickSwitcherDestinationKind.thread => 'Thread',
};

FlucordIconData _kindIcon(QuickSwitcherDestinationKind kind) => switch (kind) {
  QuickSwitcherDestinationKind.guild => FlucordIcons.server,
  QuickSwitcherDestinationKind.directMessage => FlucordIcons.mention,
  QuickSwitcherDestinationKind.textChannel => FlucordIcons.textChannel,
  QuickSwitcherDestinationKind.voiceChannel => FlucordIcons.voiceChannel,
  QuickSwitcherDestinationKind.forumChannel => FlucordIcons.forum,
  QuickSwitcherDestinationKind.mediaChannel => FlucordIcons.mediaChannel,
  QuickSwitcherDestinationKind.thread => FlucordIcons.threads,
};
