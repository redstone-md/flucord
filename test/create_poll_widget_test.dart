import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/create_poll_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('validates fields and preserves a failed poll submission', (
    tester,
  ) async {
    final submission = Completer<bool>();
    PendingPoll? submitted;
    await _pumpDialog(
      tester,
      onCreate: (poll) {
        submitted = poll;
        return submission.future;
      },
    );

    await _tapCreate(tester);
    expect(find.text('Enter a question.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('poll-question')),
      '  Which build ships?  ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll-answer-0')),
      'Stable',
    );
    await _tapCreate(tester);
    expect(find.text('Fill in every answer.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('poll-answer-1')),
      'Canary',
    );
    await tester.tap(find.byKey(const ValueKey('poll-multiselect')));
    await _tapCreate(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(submitted?.question, 'Which build ships?');
    expect(submitted?.answers, ['Stable', 'Canary']);
    expect(submitted?.allowMultiselect, isTrue);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('poll-question')))
          .enabled,
      isFalse,
    );

    submission.complete(false);
    await tester.pump();
    expect(find.text('Could not create the poll.'), findsOneWidget);
    expect(find.text('Which build ships?'), findsNothing);
  });

  testWidgets('adds and removes answer fields without dropping input', (
    tester,
  ) async {
    await _pumpDialog(tester, onCreate: (_) async => false);

    await tester.enterText(
      find.byKey(const ValueKey('poll-answer-0')),
      'Stable',
    );
    await tester.tap(find.byKey(const ValueKey('add-poll-answer')));
    await tester.pump();

    expect(find.byKey(const ValueKey('poll-answer-2')), findsOneWidget);
    expect(find.text('3/10'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('poll-answer-0')))
          .controller
          ?.text,
      'Stable',
    );

    await tester.tap(find.byTooltip('Remove answer').last);
    await tester.pump();
    expect(find.byKey(const ValueKey('poll-answer-2')), findsNothing);
    expect(find.text('2/10'), findsOneWidget);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required CreatePollCallback onCreate,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(body: CreatePollDialog(onCreate: onCreate)),
    ),
  );
}

Future<void> _tapCreate(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('create-poll-confirm'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}
