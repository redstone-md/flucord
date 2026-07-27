import 'package:flutter/material.dart';

import '../../application/message_search_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/external_link_launcher.dart';
import '../../domain/message_search.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';
import 'message_content_view.dart';
import 'message_timestamp.dart';

part 'message_search_result_views.dart';

/// The results of a server-side search, beside the timeline.
///
/// Every state the search machine can be in is drawn here, and the one that
/// matters most is "still indexing": Discord answers a query against a corpus
/// it has not finished indexing with `202 Accepted`, which is neither an error
/// nor an empty result. Showing "no results" for it would tell the reader their
/// message does not exist when the server simply has not looked yet.
class MessageSearchPanel extends StatelessWidget {
  const MessageSearchPanel({
    required this.controller,
    required this.workspace,
    required this.linkLauncher,
    required this.onClose,
    required this.onJump,
    required this.onSelectChannel,
    super.key,
  });

  final MessageSearchController controller;
  final ChatWorkspace workspace;
  final ExternalLinkLauncher linkLauncher;
  final VoidCallback onClose;

  /// Opens the timeline at one hit.
  final void Function(String channelId, String messageId) onJump;
  final ValueChanged<String> onSelectChannel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('message-search-panel'),
      width: 340,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(left: BorderSide(color: context.surfaces.border)),
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          children: [
            _header(context),
            Divider(height: 1, color: context.surfaces.border),
            if (controller.unresolved.isNotEmpty)
              _UnusableFilters(tokens: controller.unresolved),
            Expanded(child: _body(context)),
            if (controller.status == MessageSearchStatus.ready)
              _SearchPager(
                pageIndex: controller.pageIndex,
                pageCount: controller.pageCount,
                onSelectPage: controller.goToPage,
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => SizedBox(
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
                'Search results',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (_countLabel case final label?)
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: context.surfaces.muted),
                ),
            ],
          ),
        ),
        PopupMenuButton<MessageSearchSort>(
          key: const ValueKey('search-sort'),
          tooltip: 'Sort results',
          initialValue: controller.sort,
          onSelected: controller.setSort,
          itemBuilder: (context) => [
            for (final sort in MessageSearchSort.values)
              PopupMenuItem(value: sort, child: Text(_sortLabel(sort))),
          ],
          icon: const Icon(Icons.sort, size: 18),
        ),
        IconButton(
          key: const ValueKey('close-search-panel'),
          onPressed: onClose,
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Close search results',
        ),
        const SizedBox(width: 4),
      ],
    ),
  );

  /// The count Discord shows, capped: pagination cannot reach past ten
  /// thousand results, so a larger total is reported as "more than".
  String? get _countLabel {
    final results = controller.results;
    if (results == null) return null;
    final total = results.reachableTotal;
    final noun = total == 1 ? 'result' : 'results';
    return results.isTotalLimited ? 'More than $total $noun' : '$total $noun';
  }

  static String _sortLabel(MessageSearchSort sort) => switch (sort) {
    MessageSearchSort.newest => 'Newest',
    MessageSearchSort.oldest => 'Oldest',
    MessageSearchSort.mostRelevant => 'Most relevant',
  };

  Widget _body(BuildContext context) {
    switch (controller.status) {
      case MessageSearchStatus.searching:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      case MessageSearchStatus.indexing:
        return _IndexingState(
          status: controller.indexing,
          onRetry: () => controller.retry(),
        );
      case MessageSearchStatus.failed:
        return _SearchPanelState(
          icon: Icons.error_outline,
          title: 'Search unavailable',
          detail: 'The server could not answer that search.',
          action: TextButton(
            key: const ValueKey('retry-search'),
            onPressed: () => controller.retry(),
            child: const Text('Retry'),
          ),
        );
      case MessageSearchStatus.idle:
        return const _SearchPanelState(
          icon: Icons.search,
          title: 'Search this conversation',
          detail:
              'Filter with from:, mentions:, has:, in:, '
              'before:, after: and pinned:.',
        );
      case MessageSearchStatus.ready:
        final results = controller.results;
        if (results == null || results.isEmpty) {
          return const _SearchPanelState(
            icon: Icons.search_off,
            title: 'No results found',
            detail: 'Try a different word, or drop one of the filters.',
          );
        }
        return _results(context, results);
    }
  }

  Widget _results(BuildContext context, MessageSearchResults results) {
    final authors = {for (final author in results.authors) author.id: author};
    return ListView.separated(
      key: const ValueKey('search-results-list'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount:
          results.groups.length + (results.doingDeepHistoricalIndex ? 1 : 0),
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: context.surfaces.border,
      ),
      itemBuilder: (context, index) {
        if (results.doingDeepHistoricalIndex && index == 0) {
          return const _PartialIndexNotice();
        }
        final group =
            results.groups[index - (results.doingDeepHistoricalIndex ? 1 : 0)];
        return _HitGroupView(
          group: group,
          authors: authors,
          workspace: workspace,
          channelName: _channelNameFor(group.hit.channelId),
          linkLauncher: linkLauncher,
          onSelectChannel: onSelectChannel,
          onJump: onJump,
        );
      },
    );
  }

  /// The envelope names channels the workspace may never have loaded — a hit
  /// inside a thread nobody opened still has to say where it came from.
  String? _channelNameFor(String channelId) =>
      workspace.channelOrNull(channelId)?.name ??
      controller.channelNameFor(channelId);
}
