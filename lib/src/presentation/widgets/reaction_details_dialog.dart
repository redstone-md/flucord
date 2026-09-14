import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/reaction_repository.dart';
import '../../theme/flucord_theme.dart';
import 'member_avatar.dart';
import 'message_reaction_strip.dart';

typedef ReactionUsersLoader =
    Future<ReactionUsersPage> Function(
      ChatMessage message,
      MessageReaction reaction,
      DiscordReactionType type,
      String? afterUserId,
    );

class ReactionDetailsDialog extends StatefulWidget {
  const ReactionDetailsDialog({
    required this.message,
    required this.workspace,
    required this.initialReaction,
    required this.onLoad,
    super.key,
  });

  final ChatMessage message;
  final ChatWorkspace workspace;
  final MessageReaction initialReaction;
  final ReactionUsersLoader onLoad;

  static Future<void> show(
    BuildContext context, {
    required ChatMessage message,
    required ChatWorkspace workspace,
    required MessageReaction initialReaction,
    required ReactionUsersLoader onLoad,
  }) => showDialog<void>(
    context: context,
    builder: (_) => ReactionDetailsDialog(
      message: message,
      workspace: workspace,
      initialReaction: initialReaction,
      onLoad: onLoad,
    ),
  );

  @override
  State<ReactionDetailsDialog> createState() => _ReactionDetailsDialogState();
}

class _ReactionDetailsDialogState extends State<ReactionDetailsDialog> {
  late MessageReaction _selected = widget.initialReaction;
  List<Member> _normalUsers = const [];
  List<Member> _burstUsers = const [];
  bool _normalHasMore = false;
  bool _burstHasMore = false;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    final generation = reset ? ++_generation : _generation;
    if (reset) {
      _normalUsers = const [];
      _burstUsers = const [];
      _normalHasMore = false;
      _burstHasMore = false;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = <Future<_TypedReactionPage>>[];
      if (reset ? _selected.normalCount > 0 : _normalHasMore) {
        requests.add(_page(DiscordReactionType.normal, _normalUsers));
      }
      if (reset ? _selected.burstCount > 0 : _burstHasMore) {
        requests.add(_page(DiscordReactionType.burst, _burstUsers));
      }
      final pages = await Future.wait(requests);
      if (!mounted || generation != _generation) return;
      setState(() {
        for (final page in pages) {
          _applyPage(page, reset: reset);
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<_TypedReactionPage> _page(
    DiscordReactionType type,
    List<Member> current,
  ) async {
    final page = await widget.onLoad(
      widget.message,
      _selected,
      type,
      current.lastOrNull?.id,
    );
    return _TypedReactionPage(type, page);
  }

  void _applyPage(_TypedReactionPage typed, {required bool reset}) {
    final current = typed.type == DiscordReactionType.normal
        ? _normalUsers
        : _burstUsers;
    final merged = _merge(reset ? const [] : current, typed.page.users);
    final expected = typed.type == DiscordReactionType.normal
        ? _selected.normalCount
        : _selected.burstCount;
    final hasMore = typed.page.hasMore && merged.length < expected;
    if (typed.type == DiscordReactionType.normal) {
      _normalUsers = merged;
      _normalHasMore = hasMore;
    } else {
      _burstUsers = merged;
      _burstHasMore = hasMore;
    }
  }

  static List<Member> _merge(List<Member> current, List<Member> incoming) {
    final byId = {for (final member in current) member.id: member};
    for (final member in incoming) {
      byId[member.id] = member;
    }
    return List.unmodifiable(byId.values);
  }

  void _select(MessageReaction reaction) {
    if (reaction.key == _selected.key) return;
    setState(() => _selected = reaction);
    unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(540, media.width - 32),
        height: math.min(520, media.height - 32),
        child: Column(
          children: [
            _header(context),
            Divider(height: 1, color: context.surfaces.border),
            Expanded(
              child: Row(
                children: [
                  SizedBox(width: media.width < 480 ? 76 : 104, child: _rail()),
                  VerticalDivider(width: 1, color: context.surfaces.border),
                  Expanded(child: _people(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: [
        const SizedBox(width: 16),
        const Expanded(
          child: Text(
            'Reactions',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 18),
        ),
        const SizedBox(width: 4),
      ],
    ),
  );

  Widget _rail() => ListView.builder(
    padding: const EdgeInsets.symmetric(vertical: 8),
    itemCount: widget.message.reactions.length,
    itemBuilder: (context, index) {
      final reaction = widget.message.reactions[index];
      final selected = reaction.key == _selected.key;
      return Material(
        color: selected ? context.surfaces.inset : Colors.transparent,
        child: InkWell(
          key: ValueKey('reaction-detail-tab-${reaction.key}'),
          onTap: () => _select(reaction),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  width: 2,
                  color: selected ? FlucordColors.brand : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                ReactionGlyph(
                  reaction: reaction,
                  workspace: widget.workspace,
                  channelId: widget.message.channelId,
                ),
                const SizedBox(width: 8),
                Text('${reaction.count}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _people(BuildContext context) {
    final rows = [
      for (final user in _normalUsers)
        (user: user, type: DiscordReactionType.normal),
      for (final user in _burstUsers)
        (user: user, type: DiscordReactionType.burst),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _selectionSummary(context),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: rows.isEmpty
              ? _emptyState(context)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: 48,
                    color: context.surfaces.border.withValues(alpha: 0.7),
                  ),
                  itemBuilder: (context, index) => _userRow(rows[index]),
                ),
        ),
        if (_error != null) _errorRow(context),
        if ((_normalHasMore || _burstHasMore) && _error == null)
          _loadMore(context),
      ],
    );
  }

  Widget _selectionSummary(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        ReactionGlyph(
          reaction: _selected,
          workspace: widget.workspace,
          channelId: widget.message.channelId,
          size: 20,
        ),
        Text(
          '${_selected.normalCount} normal',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        if (_selected.burstCount > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 12,
                color: FlucordColors.warning,
              ),
              const SizedBox(width: 4),
              Text(
                '${_selected.burstCount} super',
                style: TextStyle(fontSize: 11, color: context.surfaces.muted),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _emptyState(BuildContext context) => Center(
    child: Text(
      _error == null && !_loading ? 'No reactions to show' : 'Loading people…',
      style: TextStyle(fontSize: 12, color: context.surfaces.muted),
    ),
  );

  Widget _userRow(({Member user, DiscordReactionType type}) row) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    child: Row(
      children: [
        MemberAvatar(member: row.user, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            row.user.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        if (row.type == DiscordReactionType.burst) ...[
          const Icon(
            Icons.auto_awesome,
            size: 11,
            color: FlucordColors.warning,
          ),
          const SizedBox(width: 4),
          const Text('Super', style: TextStyle(fontSize: 10)),
        ],
      ],
    ),
  );

  Widget _errorRow(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.surfaces.border)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, size: 15, color: FlucordColors.danger),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Could not load reactions',
            style: TextStyle(fontSize: 11),
          ),
        ),
        TextButton(
          onPressed: () => _load(reset: false),
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  Widget _loadMore(BuildContext context) => Container(
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.surfaces.border)),
    ),
    child: TextButton(
      key: const ValueKey('reaction-details-load-more'),
      onPressed: _loading ? null : () => _load(reset: false),
      child: const Text('Load more'),
    ),
  );
}

final class _TypedReactionPage {
  const _TypedReactionPage(this.type, this.page);

  final DiscordReactionType type;
  final ReactionUsersPage page;
}
