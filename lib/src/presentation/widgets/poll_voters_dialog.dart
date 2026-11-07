import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../domain/poll_repository.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_dialog.dart';
import 'paged_people_pane.dart';

/// Loads one page of the voters of [answer], after the voter [afterUserId].
typedef PollVotersLoader =
    Future<MemberPage> Function(
      ChatMessage message,
      PollAnswer answer,
      String? afterUserId,
    );

/// Who voted for each answer of a poll: the answers on the left, the voters
/// of the chosen one on the right.
class PollVotersDialog extends StatefulWidget {
  const PollVotersDialog({
    required this.message,
    required this.onLoad,
    super.key,
  });

  /// A message that carries a poll.
  final ChatMessage message;
  final PollVotersLoader onLoad;

  static Future<void> show(
    BuildContext context, {
    required ChatMessage message,
    required PollVotersLoader onLoad,
  }) => showDialog<void>(
    context: context,
    builder: (_) => PollVotersDialog(message: message, onLoad: onLoad),
  );

  @override
  State<PollVotersDialog> createState() => _PollVotersDialogState();
}

class _PollVotersDialogState extends State<PollVotersDialog> {
  late final List<PollAnswer> _answers = widget.message.poll!.answers;

  /// The first answer anybody voted for.
  late PollAnswer _selected = _answers.firstWhere(
    (answer) => answer.count > 0,
    orElse: () => _answers.first,
  );
  List<Member> _voters = const [];
  bool _hasMore = false;
  bool _loading = false;
  Object? _error;

  /// Bumped on each change of answer, so a page for the one before is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    final generation = reset ? ++_generation : _generation;
    final current = reset ? const <Member>[] : _voters;
    setState(() {
      if (reset) {
        _voters = const [];
        _hasMore = false;
      }
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.onLoad(
        widget.message,
        _selected,
        current.lastOrNull?.id,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _voters = List.unmodifiable([...current, ...page.users]);
        _hasMore = page.hasMore;
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

  void _select(PollAnswer answer) {
    if (answer.id == _selected.id) return;
    _selected = answer;
    unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    return FlucordDialog.frame(
      insetPadding: const EdgeInsets.all(16),
      actions: const [FlucordDialogCancel(label: 'Close')],
      child: SizedBox(
        width: math.min(540, media.width - 32),
        height: math.min(520, media.height - 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.message.poll!.question,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.heading.style,
              ),
            ),
            Divider(height: 1, color: context.surfaces.border),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: media.width < 480 ? 120 : 180,
                    child: _rail(),
                  ),
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

  Widget _rail() => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      for (final answer in _answers)
        Material(
          color: answer.id == _selected.id
              ? context.surfaces.inset
              : Colors.transparent,
          child: InkWell(
            key: ValueKey('poll-voters-answer-${answer.id}'),
            onTap: () => _select(answer),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
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
                    '${answer.count}',
                    style: TextStyle(
                      fontSize: FlucordType.caption,
                      color: context.surfaces.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget _people(BuildContext context) => PagedPeoplePane(
    people: [for (final voter in _voters) (member: voter, trailing: null)],
    loading: _loading,
    failed: _error != null,
    hasMore: _hasMore,
    emptyLabel: 'No votes for this answer',
    loadingLabel: 'Loading voters…',
    failureLabel: 'Could not load voters',
    onRetry: () => _load(reset: _voters.isEmpty),
    onLoadMore: () => _load(reset: false),
    loadMoreKey: const ValueKey('poll-voters-load-more'),
  );
}
