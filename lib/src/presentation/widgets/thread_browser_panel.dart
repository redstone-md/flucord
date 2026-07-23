import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

class ThreadBrowserPanel extends StatelessWidget {
  const ThreadBrowserPanel({
    required this.parentChannel,
    required this.activeThreads,
    required this.archivedThreads,
    required this.isLoading,
    required this.error,
    required this.canLoadMore,
    required this.onClose,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onSelectThread,
    super.key,
  });

  final ConversationChannel parentChannel;
  final List<ConversationChannel> activeThreads;
  final List<ConversationChannel> archivedThreads;
  final bool isLoading;
  final Object? error;
  final bool canLoadMore;
  final VoidCallback onClose;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;
  final ValueChanged<String> onSelectThread;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('thread-browser-panel'),
      width: 320,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(left: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        children: [
          _ThreadPanelHeader(
            channelName: parentChannel.name,
            onRefresh: onRefresh,
            onClose: onClose,
          ),
          Divider(height: 1, color: context.surfaces.border),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (isLoading && activeThreads.isEmpty && archivedThreads.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (error != null && activeThreads.isEmpty && archivedThreads.isEmpty) {
      return _ThreadPanelState(
        icon: Icons.error_outline,
        title: 'Threads unavailable',
        action: TextButton(onPressed: onRefresh, child: const Text('Retry')),
      );
    }
    if (activeThreads.isEmpty && archivedThreads.isEmpty) {
      return const _ThreadPanelState(
        icon: Icons.forum_outlined,
        title: 'No threads yet',
      );
    }
    return ListView(
      key: const ValueKey('thread-browser-list'),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      children: [
        if (activeThreads.isNotEmpty) ...[
          const _ThreadSectionLabel(label: 'Active threads'),
          for (final thread in activeThreads)
            _ThreadRow(
              thread: thread,
              onPressed: () => onSelectThread(thread.id),
            ),
        ],
        if (archivedThreads.isNotEmpty) ...[
          if (activeThreads.isNotEmpty) const SizedBox(height: 14),
          const _ThreadSectionLabel(label: 'Archived threads'),
          for (final thread in archivedThreads)
            _ThreadRow(
              thread: thread,
              onPressed: () => onSelectThread(thread.id),
            ),
        ],
        if (error != null)
          _InlineArchiveError(onRetry: onRefresh)
        else if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (canLoadMore)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              key: const ValueKey('load-more-archived-threads'),
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more, size: 18),
              label: const Text('Load more'),
            ),
          ),
      ],
    );
  }
}

class LockedThreadComposerNotice extends StatelessWidget {
  const LockedThreadComposerNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('locked-thread-notice'),
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: context.surfaces.surface,
      border: Border(top: BorderSide(color: context.surfaces.border)),
    ),
    child: Row(
      children: [
        Icon(Icons.lock_outline, size: 17, color: context.surfaces.muted),
        const SizedBox(width: 9),
        const Expanded(
          child: Text(
            'This archived thread is locked.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

class _ThreadPanelHeader extends StatelessWidget {
  const _ThreadPanelHeader({
    required this.channelName,
    required this.onRefresh,
    required this.onClose,
  });

  final String channelName;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: Row(
      children: [
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Threads',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              Text(
                '#$channelName',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: context.surfaces.muted),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('refresh-threads'),
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: 'Refresh threads',
        ),
        IconButton(
          key: const ValueKey('close-threads-panel'),
          onPressed: onClose,
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Close threads',
        ),
        const SizedBox(width: 4),
      ],
    ),
  );
}

class _ThreadSectionLabel extends StatelessWidget {
  const _ThreadSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        color: context.surfaces.muted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread, required this.onPressed});

  final ConversationChannel thread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: ValueKey('thread-row-${thread.id}'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          children: [
            Icon(
              thread.isArchived ? Icons.archive_outlined : Icons.forum_outlined,
              size: 18,
              color: context.surfaces.muted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    thread.isArchived
                        ? _archiveLabel(thread.archiveTimestamp)
                        : 'Active thread',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: context.surfaces.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (thread.isLocked)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.lock_outline,
                  size: 15,
                  color: context.surfaces.muted,
                ),
              ),
          ],
        ),
      ),
    ),
  );

  static String _archiveLabel(DateTime? timestamp) {
    if (timestamp == null) return 'Archived';
    final local = timestamp.toLocal();
    final month = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][local.month - 1];
    return 'Archived $month ${local.day}, ${local.year}';
  }
}

class _InlineArchiveError extends StatelessWidget {
  const _InlineArchiveError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      children: [
        Icon(Icons.error_outline, size: 16, color: context.surfaces.muted),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Archived threads unavailable',
            style: TextStyle(fontSize: 11),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

class _ThreadPanelState extends StatelessWidget {
  const _ThreadPanelState({
    required this.icon,
    required this.title,
    this.action,
  });

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 26, color: context.surfaces.muted),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontSize: 12)),
        ?action,
      ],
    ),
  );
}
