import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/message_poll_view.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('renders percentages, metadata, selection, and end action', (
    tester,
  ) async {
    var ended = false;
    await _pumpPoll(
      tester,
      poll: _poll(),
      canEnd: true,
      onEnd: () => ended = true,
    );

    expect(find.text('Which build ships?'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.textContaining('4 votes'), findsOneWidget);
    expect(find.textContaining('multiple answers'), findsOneWidget);
    final answerSemantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Stable, 75 percent, 3 votes',
      ),
    );
    expect(answerSemantics.properties.selected, isTrue);

    await tester.tap(find.byKey(const ValueKey('end-poll')));
    expect(ended, isTrue);
  });

  testWidgets('fits compact width and hides end action after finalization', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpPoll(
      tester,
      poll: _poll(finalized: true),
      canEnd: true,
      onEnd: () {},
    );

    expect(find.textContaining('Poll ended'), findsOneWidget);
    expect(find.byKey(const ValueKey('end-poll')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  group('voting', () {
    testWidgets('a tap on an answer votes for it alone', (tester) async {
      final votes = <Set<int>>[];
      await _pumpPoll(
        tester,
        poll: _poll(multiselect: false, ownVote: const {}),
        onVote: votes.add,
      );

      await tester.tap(find.byKey(const ValueKey('poll-answer-2')));

      expect(votes, [
        {2},
      ]);
      expect(find.byKey(const ValueKey('poll-remove-vote')), findsNothing);
    });

    testWidgets('a tap on another answer changes a one-answer vote', (
      tester,
    ) async {
      final votes = <Set<int>>[];
      await _pumpPoll(
        tester,
        poll: _poll(multiselect: false, ownVote: const {1}),
        onVote: votes.add,
      );

      await tester.tap(find.byKey(const ValueKey('poll-answer-2')));

      expect(votes, [
        {2},
      ]);
    });

    testWidgets('a multi-answer poll adds and drops answers one by one', (
      tester,
    ) async {
      final votes = <Set<int>>[];
      await _pumpPoll(
        tester,
        poll: _poll(multiselect: true, ownVote: const {1}),
        onVote: votes.add,
      );

      await tester.tap(find.byKey(const ValueKey('poll-answer-2')));
      await tester.tap(find.byKey(const ValueKey('poll-answer-1')));

      expect(votes, [
        {1, 2},
        <int>{},
      ]);
    });

    testWidgets('Remove vote takes the whole vote back', (tester) async {
      final votes = <Set<int>>[];
      await _pumpPoll(
        tester,
        poll: _poll(multiselect: true, ownVote: const {1, 2}),
        onVote: votes.add,
      );

      await tester.tap(find.byKey(const ValueKey('poll-remove-vote')));

      expect(votes, [<int>{}]);
    });

    testWidgets('an ended poll shows its results and takes no vote', (
      tester,
    ) async {
      final votes = <Set<int>>[];
      await _pumpPoll(
        tester,
        poll: _poll(ownVote: const {1}, expired: true),
        onVote: votes.add,
      );

      await tester.tap(find.byKey(const ValueKey('poll-answer-2')));

      expect(votes, isEmpty);
      expect(find.text('75%'), findsOneWidget);
      expect(find.textContaining('Poll ended'), findsOneWidget);
      expect(find.byKey(const ValueKey('poll-remove-vote')), findsNothing);
    });

    testWidgets('a session that cannot vote offers no vote', (tester) async {
      await _pumpPoll(tester, poll: _poll(ownVote: const {1}));

      expect(find.byKey(const ValueKey('poll-remove-vote')), findsNothing);
      expect(
        tester
            .widget<InkWell>(
              find.descendant(
                of: find.byKey(const ValueKey('poll-answer-2')),
                matching: find.byType(InkWell),
              ),
            )
            .onTap,
        isNull,
      );
    });
  });

  testWidgets('Show voters opens the list when somebody voted', (tester) async {
    var opened = 0;
    await _pumpPoll(tester, poll: _poll(), onShowVoters: () => opened++);

    await tester.tap(find.byKey(const ValueKey('poll-voters')));

    expect(opened, 1);
  });
}

Future<void> _pumpPoll(
  WidgetTester tester, {
  required MessagePoll poll,
  bool canEnd = false,
  VoidCallback? onEnd,
  ValueChanged<Set<int>>? onVote,
  VoidCallback? onShowVoters,
}) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: MessagePollView(
          poll: poll,
          canEnd: canEnd,
          onEnd: onEnd ?? () {},
          onVote: onVote,
          onShowVoters: onShowVoters,
        ),
      ),
    ),
  ),
);

/// Three votes for "Stable" and one for "Canary". [ownVote] is the account's.
MessagePoll _poll({
  bool finalized = false,
  bool expired = false,
  bool multiselect = true,
  Set<int> ownVote = const {1},
}) => MessagePoll(
  question: 'Which build ships?',
  answers: [
    PollAnswer(
      id: 1,
      text: 'Stable',
      count: 3,
      votedByCurrentUser: ownVote.contains(1),
    ),
    PollAnswer(
      id: 2,
      text: 'Canary',
      count: 1,
      votedByCurrentUser: ownVote.contains(2),
    ),
  ],
  expiry: DateTime.now().add(Duration(hours: expired ? -1 : 2)),
  allowMultiselect: multiselect,
  isFinalized: finalized,
);
