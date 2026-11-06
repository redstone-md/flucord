import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'message_row_metrics.dart';

/// A run of consecutive messages from blocked people: the rows the timeline
/// folds behind one [BlockedMessagesBar].
final class BlockedRun {
  const BlockedRun._(this.start, this.messages);

  /// Where the run starts in the timeline's messages.
  final int start;
  final List<ChatMessage> messages;

  /// Whether the reader opened this run. One opened message opens the whole
  /// run, so a run that grows on either side stays open.
  bool isOpenIn(Set<String> openMessageIds) =>
      messages.any((message) => openMessageIds.contains(message.id));
}

/// The timeline's messages cut into [BlockedRun]s. The one place that decides
/// which rows fold together.
final class BlockedMessageFold {
  BlockedMessageFold(List<ChatMessage> messages, Set<String> blockedUserIds)
    : _runs = blockedUserIds.isEmpty
          ? const []
          : _runsOf(messages, blockedUserIds);

  final List<BlockedRun?> _runs;

  /// The run the message at [index] belongs to, or null for a message that
  /// does not fold.
  BlockedRun? runAt(int index) => index < _runs.length ? _runs[index] : null;

  static List<BlockedRun?> _runsOf(
    List<ChatMessage> messages,
    Set<String> blockedUserIds,
  ) {
    bool folds(ChatMessage message) =>
        !message.isSystem && blockedUserIds.contains(message.authorId);
    final runs = List<BlockedRun?>.filled(messages.length, null);
    var index = 0;
    while (index < messages.length) {
      if (!folds(messages[index])) {
        index++;
        continue;
      }
      var end = index + 1;
      while (end < messages.length && folds(messages[end])) {
        end++;
      }
      runs.fillRange(
        index,
        end,
        BlockedRun._(index, messages.sublist(index, end)),
      );
      index = end;
    }
    return runs;
  }
}

/// The row a [BlockedRun] folds into: how many messages it holds, and the
/// control that shows or hides them.
class BlockedMessagesBar extends StatelessWidget {
  const BlockedMessagesBar({
    required this.count,
    required this.isOpen,
    required this.onToggle,
    super.key,
  });

  final int count;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MessageRowMetrics.inline,
        vertical: 6,
      ),
      child: Row(
        children: [
          SizedBox(
            width: MessageRowMetrics.avatarSize,
            child: FlucordIcon(
              FlucordIcons.block,
              size: 16,
              color: surfaces.muted,
            ),
          ),
          const SizedBox(width: MessageRowMetrics.avatarGap),
          Flexible(
            child: Text(
              count == 1 ? '1 blocked message' : '$count blocked messages',
              style: FlucordTextRole.caption.style.copyWith(
                color: surfaces.muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey('blocked-messages-toggle'),
            onPressed: onToggle,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: FlucordTextRole.caption.strong,
            ),
            child: Text(isOpen ? 'Hide' : 'Show'),
          ),
        ],
      ),
    );
  }
}
