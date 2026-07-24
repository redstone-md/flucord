import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/inbox_catalog.dart';
import '../../application/system_message_text.dart';
import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';

class InboxActivityButton extends StatelessWidget {
  const InboxActivityButton({
    required this.summary,
    required this.onPressed,
    super.key,
  });

  final InboxSummary summary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = summary.mentionCount > 0
        ? 'Inbox, ${summary.mentionCount} mentions'
        : summary.hasUnread
        ? 'Inbox, unread messages'
        : 'Inbox';
    return Semantics(
      label: label,
      button: true,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: 40,
          child: Stack(
            children: [
              Positioned.fill(
                child: IconButton(
                  key: const ValueKey('open-inbox'),
                  onPressed: onPressed,
                  icon: const Icon(Icons.inbox_outlined, size: 19),
                ),
              ),
              if (summary.mentionCount > 0)
                Positioned(
                  top: 3,
                  right: 2,
                  child: _ActivityBadge(count: summary.mentionCount),
                )
              else if (summary.hasUnread)
                Positioned(
                  top: 7,
                  right: 6,
                  child: Container(
                    key: const ValueKey('inbox-unread-indicator'),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class InboxDialog extends StatelessWidget {
  const InboxDialog({
    required this.catalog,
    required this.onMarkAllRead,
    super.key,
  });

  final InboxCatalog catalog;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    final availableHeight = MediaQuery.sizeOf(context).height - 88;
    return Semantics(
      label: 'Inbox',
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      child: Dialog(
        key: const ValueKey('inbox-dialog'),
        alignment: Alignment.topRight,
        insetPadding: const EdgeInsets.fromLTRB(24, 64, 12, 24),
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: 0.38),
        backgroundColor: context.surfaces.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 480,
          height: math.min(680, availableHeight),
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                _InboxHeader(
                  showMarkAllRead: catalog.summary.hasActivity,
                  onMarkAllRead: onMarkAllRead,
                ),
                _InboxTabs(catalog: catalog),
                Divider(height: 1, color: context.surfaces.border),
                Expanded(
                  child: TabBarView(
                    children: [
                      _UnreadList(entries: catalog.unread),
                      _MentionList(entries: catalog.mentions),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InboxHeader extends StatelessWidget {
  const _InboxHeader({
    required this.showMarkAllRead,
    required this.onMarkAllRead,
  });

  final bool showMarkAllRead;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Inbox',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          if (showMarkAllRead)
            TextButton(
              key: const ValueKey('inbox-mark-all-read'),
              onPressed: onMarkAllRead,
              child: const Text(
                'Mark all as read',
                style: TextStyle(fontSize: 11),
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('close-inbox'),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    ),
  );
}

class _InboxTabs extends StatelessWidget {
  const _InboxTabs({required this.catalog});

  final InboxCatalog catalog;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.surfaces.inset,
    child: SizedBox(
      height: 40,
      child: TabBar(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelColor: context.surfaces.muted,
        tabs: [
          Tab(text: 'Unreads  ${catalog.unread.length}'),
          Tab(text: 'Mentions  ${catalog.mentions.length}'),
        ],
      ),
    ),
  );
}

class _UnreadList extends StatelessWidget {
  const _UnreadList({required this.entries});

  final List<InboxUnreadEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _InboxEmptyState(
        icon: Icons.mark_email_read_outlined,
        title: 'You are all caught up',
        detail: 'New unread channels will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) => _UnreadRow(entry: entries[index]),
    );
  }
}

class _UnreadRow extends StatelessWidget {
  const _UnreadRow({required this.entry});

  final InboxUnreadEntry entry;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      entry.mentionCount > 0
          ? '${entry.mentionCount} mention${entry.mentionCount == 1 ? '' : 's'}'
          : 'Unread messages',
      if (entry.latestActivityAt != null)
        _relativeTime(entry.latestActivityAt!),
    ].join('  •  ');
    return Semantics(
      label: '${entry.path}, $metadata',
      button: true,
      onTap: () => Navigator.of(context).pop(entry.target),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('inbox-unread-${entry.target.channelId}'),
        onTap: () => Navigator.of(context).pop(entry.target),
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.surfaces.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: entry.mentionCount > 0
                      ? FlucordColors.mention
                      : Theme.of(context).colorScheme.onSurface,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metadata,
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _MentionList extends StatelessWidget {
  const _MentionList({required this.entries});

  final List<InboxMentionEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _InboxEmptyState(
        icon: Icons.alternate_email,
        title: 'No recent mentions',
        detail: 'Messages that mention this bot will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) => _MentionRow(entry: entries[index]),
    );
  }
}

class _MentionRow extends StatelessWidget {
  const _MentionRow({required this.entry});

  final InboxMentionEntry entry;

  @override
  Widget build(BuildContext context) {
    final preview = _messagePreview(entry.message, entry.author.displayName);
    final label =
        '${entry.author.displayName} in ${entry.path}, $preview, '
        '${_relativeTime(entry.message.sentAt)}';
    return Semantics(
      label: label,
      button: true,
      onTap: () => Navigator.of(context).pop(entry.target),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('inbox-mention-${entry.message.id}'),
        onTap: () => Navigator.of(context).pop(entry.target),
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.surfaces.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberAvatar(
                member: entry.author,
                spaceId: entry.target.spaceId,
                size: 32,
                showPresence: false,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.author.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          _relativeTime(entry.message.sentAt),
                          style: TextStyle(
                            color: context.surfaces.muted,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: FlucordColors.mention,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _messagePreview(ChatMessage message, String authorName) {
  if (message.isSystem) return SystemMessageText.describe(message, authorName);
  final body = message.body.trim();
  if (body.isNotEmpty) return body;
  final question = message.poll?.question.trim();
  if (question != null && question.isNotEmpty) return question;
  if (message.stickers.isNotEmpty) return message.stickers.first.name;
  return 'Attachment or embed';
}

class _InboxEmptyState extends StatelessWidget {
  const _InboxEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 30, color: context.surfaces.muted),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          detail,
          style: TextStyle(color: context.surfaces.muted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _ActivityBadge extends StatelessWidget {
  const _ActivityBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('inbox-mention-badge'),
    constraints: const BoxConstraints(minWidth: 16),
    height: 16,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: FlucordColors.mention,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'now';
  if (difference.inHours < 1) return '${difference.inMinutes}m';
  if (difference.inDays < 1) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return '${value.month}/${value.day}/${value.year}';
}
