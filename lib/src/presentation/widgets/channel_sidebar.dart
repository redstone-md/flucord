import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/chat_repository.dart';
import '../../application/connection_controller.dart';
import '../../theme/flucord_theme.dart';
import 'account_panel.dart';
import 'member_avatar.dart';

class ChannelSidebar extends StatelessWidget {
  const ChannelSidebar({
    required this.space,
    required this.channels,
    required this.selectedChannelId,
    required this.onSelectChannel,
    required this.sessionMode,
    required this.connectionStatus,
    required this.workspace,
    required this.collapsedCategoryIds,
    required this.onToggleCategory,
    required this.onNewDirectMessage,
    super.key,
  });

  final CommunitySpace space;
  final List<ConversationChannel> channels;
  final String? selectedChannelId;
  final ValueChanged<String> onSelectChannel;
  final SessionMode sessionMode;
  final RepositoryConnectionStatus connectionStatus;
  final ChatWorkspace workspace;
  final Set<String> collapsedCategoryIds;
  final ValueChanged<String> onToggleCategory;
  final VoidCallback onNewDirectMessage;

  @override
  Widget build(BuildContext context) {
    final isDirect = space.isDirectMessages;
    final regularChannels = channels
        .where((channel) => !channel.isThread)
        .toList(growable: false);
    final threads = channels
        .where(
          (channel) =>
              channel.isThread && !channel.isArchived && !_isForumPost(channel),
        )
        .toList(growable: false);
    return Container(
      key: const ValueKey('channel-sidebar'),
      width: 236,
      decoration: BoxDecoration(
        color: context.surfaces.surface,
        border: Border(right: BorderSide(color: context.surfaces.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.surfaces.border),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    space.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isDirect)
                  IconButton(
                    key: const ValueKey('new-direct-message'),
                    onPressed: onNewDirectMessage,
                    icon: const Icon(Icons.edit_square),
                    tooltip: 'New message',
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
              children: _navigationEntries(
                isDirect: isDirect,
                regularChannels: regularChannels,
                threads: threads,
              ),
            ),
          ),
          AccountPanel(
            member: workspace.memberById(workspace.currentMemberId),
            sessionMode: sessionMode,
            connectionStatus: connectionStatus,
          ),
        ],
      ),
    );
  }

  bool _isForumPost(ConversationChannel channel) {
    final parentId = channel.parentId;
    if (parentId == null) return false;
    final parent = workspace.channelOrNull(parentId);
    return parent?.kind == ChannelKind.forum ||
        parent?.kind == ChannelKind.media;
  }

  List<Widget> _navigationEntries({
    required bool isDirect,
    required List<ConversationChannel> regularChannels,
    required List<ConversationChannel> threads,
  }) {
    if (isDirect) {
      return [
        const _SectionLabel(label: 'Messages'),
        for (final channel in regularChannels) _rowFor(channel),
      ];
    }
    final categories = [...workspace.categoriesFor(space.id)]
      ..sort((left, right) => left.position.compareTo(right.position));
    if (categories.isEmpty) {
      return _uncategorizedEntries(regularChannels, threads);
    }
    final categoryIds = categories.map((category) => category.id).toSet();
    final uncategorized = _ordered(
      regularChannels.where(
        (channel) =>
            channel.parentId == null || !categoryIds.contains(channel.parentId),
      ),
    );
    return [
      if (uncategorized.isNotEmpty) ...[
        const _SectionLabel(label: 'Channels'),
        for (final channel in uncategorized) _rowFor(channel),
        const SizedBox(height: 10),
      ],
      for (final category in categories)
        _CategorySection(
          category: category,
          collapsed: collapsedCategoryIds.contains(category.id),
          onToggle: () => onToggleCategory(category.id),
          children: [
            for (final channel in _visibleCategoryChannels(
              category,
              regularChannels,
            ))
              _rowFor(channel),
          ],
        ),
      if (threads.isNotEmpty) ...[
        const SizedBox(height: 10),
        const _SectionLabel(label: 'Active threads'),
        for (final channel in _ordered(threads))
          _rowFor(channel, indented: true),
      ],
    ];
  }

  List<Widget> _uncategorizedEntries(
    List<ConversationChannel> channels,
    List<ConversationChannel> threads,
  ) {
    final text = _ordered(
      channels.where((channel) => channel.kind == ChannelKind.text),
    );
    final voice = _ordered(
      channels.where((channel) => channel.kind == ChannelKind.voice),
    );
    final forums = _ordered(
      channels.where(
        (channel) =>
            channel.kind == ChannelKind.forum ||
            channel.kind == ChannelKind.media,
      ),
    );
    return [
      if (text.isNotEmpty) ...[
        const _SectionLabel(label: 'Text channels'),
        for (final channel in text) _rowFor(channel),
      ],
      if (threads.isNotEmpty) ...[
        const SizedBox(height: 18),
        const _SectionLabel(label: 'Active threads'),
        for (final channel in _ordered(threads))
          _rowFor(channel, indented: true),
      ],
      if (forums.isNotEmpty) ...[
        const SizedBox(height: 18),
        const _SectionLabel(label: 'Forums'),
        for (final channel in forums) _rowFor(channel),
      ],
      if (voice.isNotEmpty) ...[
        const SizedBox(height: 18),
        const _SectionLabel(label: 'Voice channels'),
        for (final channel in voice) _rowFor(channel),
      ],
    ];
  }

  List<ConversationChannel> _visibleCategoryChannels(
    ChannelCategory category,
    List<ConversationChannel> channels,
  ) {
    final collapsed = collapsedCategoryIds.contains(category.id);
    return _ordered(
      channels.where(
        (channel) =>
            channel.parentId == category.id &&
            (!collapsed ||
                channel.id == selectedChannelId ||
                channel.unread ||
                channel.mentionCount > 0),
      ),
    );
  }

  List<ConversationChannel> _ordered(Iterable<ConversationChannel> source) =>
      source.toList(growable: false)..sort((left, right) {
        final position = left.position.compareTo(right.position);
        return position == 0 ? left.name.compareTo(right.name) : position;
      });

  _ChannelRow _rowFor(ConversationChannel channel, {bool indented = false}) =>
      _ChannelRow(
        channel: channel,
        selected: channel.id == selectedChannelId,
        recipient: channel.recipientId == null
            ? null
            : workspace.memberOrNull(channel.recipientId!),
        indented: indented,
        onPressed: () => onSelectChannel(channel.id),
      );
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
  });

  final ConversationChannel channel;
  final bool selected;
  final VoidCallback onPressed;
  final Member? recipient;
  final bool indented;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Theme.of(context).colorScheme.onSurface
        : channel.unread
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
                      fontWeight: channel.unread || selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
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
}
