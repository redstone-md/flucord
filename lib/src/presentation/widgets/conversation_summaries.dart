import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/conversation_summary.dart';
import '../../theme/flucord_theme.dart';

/// The summaries Discord has written about this channel, above its timeline.
///
/// Summaries arrive from the server without being asked for, so the strip is
/// drawn from the store as it stands: a channel with none draws nothing at
/// all, exactly the timeline it always had. Selecting a summary takes the
/// reader to the message it starts at.
class ConversationSummaries extends StatelessWidget {
  const ConversationSummaries({
    required this.workspace,
    required this.summaries,
    required this.onSelect,
    super.key,
  });

  final ChatWorkspace workspace;
  final List<ConversationSummary> summaries;
  final ValueChanged<ConversationSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('conversation-summaries'),
      height: 128,
      decoration: BoxDecoration(
        color: context.surfaces.canvas,
        border: Border(bottom: BorderSide(color: context.surfaces.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: summaries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => _SummaryCard(
          summary: summaries[index],
          participantNames: _namesOf(summaries[index]),
          onSelect: onSelect,
        ),
      ),
    );
  }

  /// Who took part, in the order Discord listed them. Somebody the workspace
  /// no longer knows is left out rather than named by an id.
  String _namesOf(ConversationSummary summary) => [
    for (final id in summary.participantIds)
      ?workspace.memberOrNull(id)?.displayName,
  ].join(' · ');
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.participantNames,
    required this.onSelect,
  });

  final ConversationSummary summary;
  final String participantNames;
  final ValueChanged<ConversationSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    // A summary with no starting message has nowhere to take the reader, so
    // it stays a plain card rather than a button that does nothing.
    final canJump = summary.startMessageId.isNotEmpty;
    return SizedBox(
      width: 300,
      child: Material(
        color: context.surfaces.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: context.surfaces.border),
        ),
        child: InkWell(
          key: ValueKey('conversation-summary-${summary.id}'),
          onTap: canJump ? () => onSelect(summary) : null,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 13,
                      color: FlucordColors.brand,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        summary.topic,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (canJump) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: context.surfaces.muted,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  summary.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.surfaces.muted),
                ),
                if (participantNames.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    participantNames,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.surfaces.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
