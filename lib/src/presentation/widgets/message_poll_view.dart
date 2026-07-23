import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

class MessagePollView extends StatelessWidget {
  const MessagePollView({
    required this.poll,
    required this.canEnd,
    required this.onEnd,
    super.key,
  });

  final MessagePoll poll;
  final bool canEnd;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final total = poll.totalVotes;
    final ended = poll.isFinalized || _hasExpired(poll.expiry);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll_outlined, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  poll.question,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final answer in poll.answers) ...[
            _PollAnswerRow(answer: answer, total: total),
            if (answer != poll.answers.last) const SizedBox(height: 5),
          ],
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  _statusText(total, ended),
                  style: TextStyle(color: context.surfaces.muted, fontSize: 10),
                ),
              ),
              if (canEnd && !ended)
                TextButton(
                  key: const ValueKey('end-poll'),
                  onPressed: onEnd,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 10),
                  ),
                  child: const Text('End poll'),
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

  static bool _hasExpired(DateTime? expiry) =>
      expiry != null && !expiry.isAfter(DateTime.now());

  static String _remaining(DateTime? expiry) {
    if (expiry == null) return 'No end time';
    final remaining = expiry.difference(DateTime.now());
    if (remaining.inMinutes < 1) return 'Ends soon';
    if (remaining.inHours < 1) return 'Ends in ${remaining.inMinutes}m';
    if (remaining.inDays < 1) return 'Ends in ${remaining.inHours}h';
    return 'Ends in ${remaining.inDays}d';
  }
}

class _PollAnswerRow extends StatelessWidget {
  const _PollAnswerRow({required this.answer, required this.total});

  final PollAnswer answer;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : answer.count / total;
    final percent = (fraction * 100).round();
    return Semantics(
      label: '${answer.text}, $percent percent, ${answer.count} votes',
      selected: answer.votedByCurrentUser,
      child: Container(
        key: ValueKey('poll-answer-${answer.id}'),
        height: 38,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.surfaces.inset,
          border: Border.all(
            color: answer.votedByCurrentUser
                ? FlucordColors.brand.withValues(alpha: 0.75)
                : context.surfaces.border,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0, 1),
                child: ColoredBox(
                  color: FlucordColors.brand.withValues(alpha: 0.14),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  if (answer.emojiName case final emoji?) ...[
                    Text(emoji, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 7),
                  ],
                  Expanded(
                    child: Text(
                      answer.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$percent%',
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
