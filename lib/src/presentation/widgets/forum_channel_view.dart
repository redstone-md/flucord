import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'create_forum_post_dialog.dart';
import 'forum_post_tile.dart';

class ForumChannelView extends StatefulWidget {
  const ForumChannelView({
    required this.workspace,
    required this.channel,
    required this.archivedPosts,
    required this.isLoading,
    required this.error,
    required this.canLoadMore,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onOpenPost,
    required this.onLoadPostPreview,
    required this.onCreatePost,
    super.key,
  });

  final ChatWorkspace workspace;
  final ConversationChannel channel;
  final List<ConversationChannel> archivedPosts;
  final bool isLoading;
  final Object? error;
  final bool canLoadMore;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;
  final ValueChanged<String> onOpenPost;
  final ValueChanged<String> onLoadPostPreview;
  final CreateForumPostCallback onCreatePost;

  @override
  State<ForumChannelView> createState() => _ForumChannelViewState();
}

class _ForumChannelViewState extends State<ForumChannelView> {
  final Set<String> _selectedTagIds = {};

  @override
  void didUpdateWidget(covariant ForumChannelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) _selectedTagIds.clear();
  }

  List<ConversationChannel> get _activePosts => widget.workspace.channels
      .where(
        (candidate) =>
            candidate.isThread &&
            !candidate.isArchived &&
            candidate.parentId == widget.channel.id,
      )
      .where(_matchesTags)
      .toList(growable: false);

  List<ConversationChannel> get _archivedPosts =>
      widget.archivedPosts.where(_matchesTags).toList(growable: false);

  bool _matchesTags(ConversationChannel post) =>
      _selectedTagIds.every(post.appliedTagIds.contains);

  Future<void> _createPost() => CreateForumPostDialog.show(
    context,
    channel: widget.channel,
    onCreate: widget.onCreatePost,
  );

  @override
  Widget build(BuildContext context) {
    final active = _activePosts;
    final archived = _archivedPosts;
    return Column(
      children: [
        _ForumToolbar(
          channel: widget.channel,
          selectedTagIds: _selectedTagIds,
          onToggleTag: (tagId) => setState(() {
            if (!_selectedTagIds.add(tagId)) _selectedTagIds.remove(tagId);
          }),
          onCreatePost: _createPost,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final usesGallery =
                  widget.channel.kind == ChannelKind.media ||
                  widget.channel.defaultForumLayout == ForumLayout.galleryView;
              final columns = usesGallery
                  ? constraints.maxWidth >= 1040
                        ? 3
                        : constraints.maxWidth >= 620
                        ? 2
                        : 1
                  : 1;
              return _ForumPostSlivers(
                workspace: widget.workspace,
                channel: widget.channel,
                activePosts: active,
                archivedPosts: archived,
                columns: columns,
                usesGallery: usesGallery,
                isLoading: widget.isLoading,
                error: widget.error,
                canLoadMore: widget.canLoadMore,
                hasTagFilter: _selectedTagIds.isNotEmpty,
                onRefresh: widget.onRefresh,
                onLoadMore: widget.onLoadMore,
                onOpenPost: widget.onOpenPost,
                onLoadPostPreview: widget.onLoadPostPreview,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ForumToolbar extends StatelessWidget {
  const _ForumToolbar({
    required this.channel,
    required this.selectedTagIds,
    required this.onToggleTag,
    required this.onCreatePost,
  });

  final ConversationChannel channel;
  final Set<String> selectedTagIds;
  final ValueChanged<String> onToggleTag;
  final VoidCallback onCreatePost;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    decoration: BoxDecoration(
      color: context.surfaces.canvas,
      border: Border(bottom: BorderSide(color: context.surfaces.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                channel.topic.isEmpty
                    ? 'Start a post to open a focused discussion.'
                    : channel.topic,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.surfaces.muted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const ValueKey('create-forum-post'),
              onPressed: onCreatePost,
              icon: const Icon(Icons.add, size: 17),
              label: const Text('New post'),
            ),
          ],
        ),
        if (channel.availableTags.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: channel.availableTags.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final tag = channel.availableTags[index];
                return FilterChip(
                  key: ValueKey('forum-filter-${tag.id}'),
                  selected: selectedTagIds.contains(tag.id),
                  onSelected: (_) => onToggleTag(tag.id),
                  label: Text(tag.name),
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),
        ],
      ],
    ),
  );
}

class _ForumPostSlivers extends StatelessWidget {
  const _ForumPostSlivers({
    required this.workspace,
    required this.channel,
    required this.activePosts,
    required this.archivedPosts,
    required this.columns,
    required this.usesGallery,
    required this.isLoading,
    required this.error,
    required this.canLoadMore,
    required this.hasTagFilter,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onOpenPost,
    required this.onLoadPostPreview,
  });

  final ChatWorkspace workspace;
  final ConversationChannel channel;
  final List<ConversationChannel> activePosts;
  final List<ConversationChannel> archivedPosts;
  final int columns;
  final bool usesGallery;
  final bool isLoading;
  final Object? error;
  final bool canLoadMore;
  final bool hasTagFilter;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;
  final ValueChanged<String> onOpenPost;
  final ValueChanged<String> onLoadPostPreview;

  @override
  Widget build(BuildContext context) {
    if (isLoading && activePosts.isEmpty && archivedPosts.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (error != null && activePosts.isEmpty && archivedPosts.isEmpty) {
      return _ForumState(
        icon: Icons.error_outline,
        title: 'Posts unavailable',
        action: TextButton(onPressed: onRefresh, child: const Text('Retry')),
      );
    }
    if (activePosts.isEmpty && archivedPosts.isEmpty) {
      return _ForumState(
        icon: hasTagFilter ? Icons.filter_alt_off : Icons.forum_outlined,
        title: hasTagFilter ? 'No posts match these tags' : 'No posts yet',
      );
    }
    return CustomScrollView(
      key: const ValueKey('forum-post-feed'),
      slivers: [
        if (activePosts.isNotEmpty) ...[
          const _ForumSectionSliver(label: 'Active posts'),
          _postGrid(activePosts),
        ],
        if (archivedPosts.isNotEmpty) ...[
          const _ForumSectionSliver(label: 'Archived posts'),
          _postGrid(archivedPosts),
        ],
        SliverToBoxAdapter(
          child: _ForumFooter(
            isLoading: isLoading,
            error: error,
            canLoadMore: canLoadMore,
            onRefresh: onRefresh,
            onLoadMore: onLoadMore,
          ),
        ),
      ],
    );
  }

  SliverPadding _postGrid(List<ConversationChannel> posts) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    sliver: SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: usesGallery ? 244 : 108,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => ForumPostTile(
          workspace: workspace,
          parent: channel,
          post: posts[index],
          gallery: usesGallery,
          onPressed: () => onOpenPost(posts[index].id),
          onLoadPreview: () => onLoadPostPreview(posts[index].id),
        ),
        childCount: posts.length,
      ),
    ),
  );
}

class _ForumSectionSliver extends StatelessWidget {
  const _ForumSectionSliver({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _ForumFooter extends StatelessWidget {
  const _ForumFooter({
    required this.isLoading,
    required this.error,
    required this.canLoadMore,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final bool isLoading;
  final Object? error;
  final bool canLoadMore;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: error != null
          ? TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry archived posts'),
            )
          : isLoading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : canLoadMore
          ? TextButton.icon(
              key: const ValueKey('load-more-forum-posts'),
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more, size: 18),
              label: const Text('Load more posts'),
            )
          : const SizedBox.shrink(),
    ),
  );
}

class _ForumState extends StatelessWidget {
  const _ForumState({required this.icon, required this.title, this.action});

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 28, color: context.surfaces.muted),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontSize: 12)),
        ?action,
      ],
    ),
  );
}
