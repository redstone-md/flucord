import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// A poll with its results. A tap on an answer votes while the poll is open.
class MessagePollView extends StatelessWidget {
  const MessagePollView({
    required this.poll,
    required this.canEnd,
    required this.onEnd,
    this.onVote,
    this.onShowVoters,
    super.key,
  });

  final MessagePoll poll;
  final bool canEnd;
  final VoidCallback onEnd;

  /// Sends the account's whole new vote, or null where the session cannot
  /// vote. An empty set takes the vote back.
  final ValueChanged<Set<int>>? onVote;

  /// Opens the list of who voted, or null where the session cannot list it.
  final VoidCallback? onShowVoters;

  @override
  Widget build(BuildContext context) {
    final total = poll.totalVotes;
    final ended = !poll.isOpenAt(DateTime.now());
    final vote = ended ? null : onVote;
    final ownVote = poll.ownVote;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FlucordIcon(FlucordIcons.poll, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(poll.question, style: FlucordTextRole.label.strong),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final answer in poll.answers) ...[
            _PollAnswerRow(
              answer: answer,
              total: total,
              onTap: vote == null
                  ? null
                  : () => vote(_toggled(ownVote, answer)),
            ),
            if (answer != poll.answers.last) const SizedBox(height: 5),
          ],
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  _statusText(total, ended),
                  style: TextStyle(
                    color: context.surfaces.muted,
                    fontSize: FlucordType.caption,
                  ),
                ),
              ),
              if (onShowVoters case final show? when total > 0)
                _PollTextButton(
                  key: const ValueKey('poll-voters'),
                  label: 'Show voters',
                  onPressed: show,
                ),
              if (vote != null && ownVote.isNotEmpty)
                _PollTextButton(
                  key: const ValueKey('poll-remove-vote'),
                  label: 'Remove vote',
                  onPressed: () => vote(const {}),
                ),
              if (canEnd && !ended)
                _PollTextButton(
                  key: const ValueKey('end-poll'),
                  label: 'End poll',
                  onPressed: onEnd,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusText(int total, bool ended) {
    final votes = '$total ${total == 1 ? 'vote' : 'votes'}';
    final selection = poll.allowMultiselect ? 'multiple answers' : 'one answer';
    if (ended) return '$votes · Poll ended · $selection';
    final expiry = poll.expiry;
    return '$votes · ${_remaining(expiry)} · $selection';
  }

  /// The vote after a tap on [answer]. A one-answer poll moves the vote to
  /// it; a tap on the answer already chosen takes that answer back.
  Set<int> _toggled(Set<int> ownVote, PollAnswer answer) {
    if (ownVote.contains(answer.id)) return {...ownVote}..remove(answer.id);
    return poll.allowMultiselect ? {...ownVote, answer.id} : {answer.id};
  }

  static String _remaining(DateTime? expiry) {
    if (expiry == null) return 'No end time';
    final remaining = expiry.difference(DateTime.now());
    if (remaining.inMinutes < 1) return 'Ends soon';
    if (remaining.inHours < 1) return 'Ends in ${remaining.inMinutes}m';
    if (remaining.inDays < 1) return 'Ends in ${remaining.inHours}h';
    return 'Ends in ${remaining.inDays}d';
  }
}

class _PollTextButton extends StatelessWidget {
  const _PollTextButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 28),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: const TextStyle(fontSize: FlucordType.caption),
    ),
    child: Text(label),
  );
}

class _PollAnswerRow extends StatelessWidget {
  const _PollAnswerRow({
    required this.answer,
    required this.total,
    required this.onTap,
  });

  final PollAnswer answer;
  final int total;

  /// Votes, or null when the answer takes no vote.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : answer.count / total;
    final percent = (fraction * 100).round();
    return Semantics(
      label: '${answer.text}, $percent percent, ${answer.count} votes',
      selected: answer.votedByCurrentUser,
      button: onTap != null,
      child: Container(
        key: ValueKey('poll-answer-${answer.id}'),
        height: 38,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.surfaces.inset,
          border: Border.all(
            color: answer.votedByCurrentUser
                ? context.surfaces.brand.withValues(alpha: 0.75)
                : context.surfaces.border,
          ),
          borderRadius: FlucordRadius.small,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0, 1),
                child: ColoredBox(
                  color: context.surfaces.brand.withValues(alpha: 0.14),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  if (answer.emojiName case final emoji?) ...[
                    Text(
                      emoji,
                      style: const TextStyle(fontSize: FlucordType.label),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      answer.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FlucordTextRole.caption.strong,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$percent%',
                    style: FlucordTextRole.caption.strong.copyWith(
                      color: context.surfaces.muted,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap),
            ),
          ],
        ),
      ),
    );
  }
}
