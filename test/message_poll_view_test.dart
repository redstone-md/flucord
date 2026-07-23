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
}

Future<void> _pumpPoll(
  WidgetTester tester, {
  required MessagePoll poll,
  required bool canEnd,
  required VoidCallback onEnd,
}) => tester.pumpWidget(
  MaterialApp(
    theme: FlucordTheme.dark,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: MessagePollView(poll: poll, canEnd: canEnd, onEnd: onEnd),
      ),
    ),
  ),
);

MessagePoll _poll({bool finalized = false}) => MessagePoll(
  question: 'Which build ships?',
  answers: const [
    PollAnswer(id: 1, text: 'Stable', count: 3, votedByCurrentUser: true),
    PollAnswer(id: 2, text: 'Canary', count: 1),
  ],
  expiry: DateTime.now().add(const Duration(hours: 2)),
  allowMultiselect: true,
  isFinalized: finalized,
);
