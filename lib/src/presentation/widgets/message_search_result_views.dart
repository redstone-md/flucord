part of 'message_search_panel.dart';

/// One hit and the messages the server sent around it.
///
/// The group is drawn in the order it arrived and the match is the one message
/// drawn at full strength: where the hit sits inside its group is not
/// established, so nothing here reorders the conversation to put it first.
class _HitGroupView extends StatelessWidget {
  const _HitGroupView({
    required this.group,
    required this.authors,
    required this.workspace,
    required this.channelName,
    required this.linkLauncher,
    required this.onSelectChannel,
    required this.onJump,
  });

  final MessageSearchHitGroup group;
  final Map<String, Member> authors;
  final ChatWorkspace workspace;
  final String? channelName;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;
  final void Function(String channelId, String messageId) onJump;

  @override
  Widget build(BuildContext context) {
    final hit = group.hit;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  channelName == null ? 'Unknown channel' : '#$channelName',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.surfaces.muted,
                  ),
                ),
              ),
              TextButton(
                key: ValueKey('jump-to-${hit.id}'),
                onPressed: () => onJump(hit.channelId, hit.id),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Jump', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          for (var index = 0; index < group.messages.length; index++)
            _SearchMessageRow(
              message: group.messages[index],
              author: _authorOf(group.messages[index]),
              spaceId: _spaceIdOf(group.messages[index]),
              workspace: workspace,
              linkLauncher: linkLauncher,
              onSelectChannel: onSelectChannel,
              isHit: index == group.hitIndex,
            ),
        ],
      ),
    );
  }

  /// Authors come off the search envelope first: a hit in a channel this
  /// session never opened has an author the workspace has never heard of.
  Member? _authorOf(ChatMessage message) =>
      authors[message.authorId] ?? workspace.memberOrNull(message.authorId);

  String? _spaceIdOf(ChatMessage message) =>
      workspace.channelOrNull(message.channelId)?.spaceId;
}

class _SearchMessageRow extends StatelessWidget {
  const _SearchMessageRow({
    required this.message,
    required this.author,
    required this.spaceId,
    required this.workspace,
    required this.linkLauncher,
    required this.onSelectChannel,
    required this.isHit,
  });

  final ChatMessage message;
  final Member? author;
  final String? spaceId;
  final ChatWorkspace workspace;
  final ExternalLinkLauncher linkLauncher;
  final ValueChanged<String> onSelectChannel;
  final bool isHit;

  @override
  Widget build(BuildContext context) {
    final muted = context.surfaces.muted;
    return Container(
      key: ValueKey('search-hit-${message.id}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: isHit
          ? BoxDecoration(
              color: context.surfaces.raised,
              borderRadius: BorderRadius.circular(5),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (author case final member?)
            MemberAvatar(member: member, size: 26, spaceId: spaceId)
          else
            const SizedBox.square(
              dimension: 26,
              child: Icon(Icons.person_outline, size: 16),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        author?.displayName ?? 'Unknown user',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isHit ? null : muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      MessageTimestamp.of(context, message.sentAt),
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
                if (message.body.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 96),
                    child: ClipRect(
                      child: MessageContentView(
                        body: message.body,
                        workspace: workspace,
                        linkLauncher: linkLauncher,
                        onSelectChannel: onSelectChannel,
                        textStyle: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: isHit ? null : muted,
                        ),
                      ),
                    ),
                  ),
                if (message.body.isEmpty && message.attachments.isNotEmpty)
                  Text(
                    message.attachments.first.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pages through the result set.
///
/// Discord walks search results in fixed blocks of 25 and refuses to go past
/// the four-hundredth page, so the pager offers exactly what the server can be
/// asked for rather than a page count derived from the raw total.
class _SearchPager extends StatelessWidget {
  const _SearchPager({
    required this.pageIndex,
    required this.pageCount,
    required this.onSelectPage,
  });

  final int pageIndex;
  final int pageCount;
  final ValueChanged<int> onSelectPage;

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 1) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('search-pager'),
      height: 44,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.surfaces.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('search-previous-page'),
            onPressed: pageIndex == 0
                ? null
                : () => onSelectPage(pageIndex - 1),
            icon: const Icon(Icons.chevron_left, size: 18),
            tooltip: 'Previous page',
          ),
          Text(
            'Page ${pageIndex + 1} of $pageCount',
            style: const TextStyle(fontSize: 11),
          ),
          IconButton(
            key: const ValueKey('search-next-page'),
            onPressed: pageIndex >= pageCount - 1
                ? null
                : () => onSelectPage(pageIndex + 1),
            icon: const Icon(Icons.chevron_right, size: 18),
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}

/// The 202 surface. Named plainly, because the one thing it must never look
/// like is an empty result set.
class _IndexingState extends StatelessWidget {
  const _IndexingState({required this.status, required this.onRetry});

  final MessageSearchIndexing? status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _SearchPanelState(
    key: const ValueKey('search-indexing'),
    icon: Icons.hourglass_top,
    title: 'Still indexing',
    detail:
        'Discord has not finished indexing these messages yet. '
        'Results will be incomplete until it does.',
    action: TextButton(
      key: const ValueKey('retry-search'),
      onPressed: onRetry,
      child: const Text('Try again'),
    ),
  );
}

/// A 200 that still admits the index is being backfilled. Unlike the 202 this
/// arrives *with* results, so it is a caveat above them rather than a state.
class _PartialIndexNotice extends StatelessWidget {
  const _PartialIndexNotice();

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('search-partial-index'),
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(
      children: [
        Icon(Icons.hourglass_bottom, size: 14, color: context.surfaces.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Older messages are still being indexed.',
            style: TextStyle(fontSize: 11, color: context.surfaces.muted),
          ),
        ),
      ],
    ),
  );
}

/// Filter words the query could not carry, listed instead of dropped: a
/// filter Discord never received would have widened the search silently.
class _UnusableFilters extends StatelessWidget {
  const _UnusableFilters({required this.tokens});

  final List<String> tokens;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('search-unusable-filters'),
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Text(
      'Ignored: ${tokens.join(', ')}',
      style: TextStyle(fontSize: 11, color: context.surfaces.muted),
    ),
  );
}

class _SearchPanelState extends StatelessWidget {
  const _SearchPanelState({
    required this.icon,
    required this.title,
    this.detail,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: context.surfaces.muted),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (detail case final text?) ...[
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: context.surfaces.muted),
            ),
          ],
          ?action,
        ],
      ),
    ),
  );
}
