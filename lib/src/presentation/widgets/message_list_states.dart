part of 'message_list.dart';

class _HistoryBoundary extends StatelessWidget {
  const _HistoryBoundary({
    required this.isLoading,
    required this.error,
    required this.onLoad,
  });

  final bool isLoading;
  final Object? error;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('history-boundary'),
      height: 48,
      child: Center(
        child: isLoading
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : error != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Older messages unavailable',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: FlucordType.caption,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const ValueKey('retry-older-messages'),
                    onPressed: onLoad,
                    tooltip: 'Retry older messages',
                    icon: const FlucordIcon(FlucordIcons.refresh, size: 16),
                  ),
                ],
              )
            : TextButton.icon(
                key: const ValueKey('load-older-messages'),
                onPressed: onLoad,
                icon: const FlucordIcon(FlucordIcons.jumpUp, size: 14),
                label: const Text(
                  'Load older messages',
                  style: TextStyle(fontSize: FlucordType.caption),
                ),
              ),
      ),
    );
  }
}

class _ChannelStart extends StatelessWidget {
  const _ChannelStart({required this.channel});

  final ConversationChannel channel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FlucordIcon(
            channel.isThread ? FlucordIcons.threads : FlucordIcons.textChannel,
            size: 28,
            color: context.surfaces.muted,
          ),
          const SizedBox(height: 12),
          Text(
            '${channel.isThread ? '' : '# '}${channel.name}',
            style: const TextStyle(
              fontSize: FlucordType.display,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            channel.topic,
            style: TextStyle(
              color: context.surfaces.muted,
              fontSize: FlucordType.label,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageEmptyState extends StatelessWidget {
  const _MessageEmptyState({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      // A short window at a large font has less height than this text needs.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlucordIcon(
              hasQuery ? FlucordIcons.noResults : FlucordIcons.chat,
              size: 30,
              color: context.surfaces.muted,
            ),
            const SizedBox(height: 12),
            Text(
              hasQuery ? 'No matching messages' : 'No messages yet',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              hasQuery
                  ? 'Try a different phrase, author, or filename.'
                  : 'Start the conversation from the field below.',
              style: TextStyle(
                color: context.surfaces.muted,
                fontSize: FlucordType.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
