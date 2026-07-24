import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';

void main() {
  testWidgets('creates and ends a poll from the native conversation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-poll')));
    await tester.pumpAndSettle();
    expect(find.text('Create a poll'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('poll-question')),
      'Which build ships?',
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll-answer-0')),
      'Stable',
    );
    await tester.enterText(
      find.byKey(const ValueKey('poll-answer-1')),
      'Canary',
    );
    await tester.tap(find.byKey(const ValueKey('poll-multiselect')));
    await tester.tap(find.byKey(const ValueKey('create-poll-confirm')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Which build ships?'), findsOneWidget);
    expect(find.text('Stable'), findsOneWidget);
    expect(find.text('Canary'), findsOneWidget);
    expect(find.textContaining('multiple answers'), findsOneWidget);
    expect(find.byKey(const ValueKey('end-poll')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('end-poll')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.textContaining('Poll ended'), findsOneWidget);
    expect(find.byKey(const ValueKey('end-poll')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
