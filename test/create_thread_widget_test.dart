import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/presentation/widgets/create_thread_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('creates a thread from a message and navigates into it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FlucordApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('message-m4'))),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-thread-m4')));
    await tester.pumpAndSettle();

    expect(find.text('Create thread'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('thread-name')),
      'Release follow-up',
    );
    await tester.tap(find.text('3 days'));
    await tester.tap(find.byKey(const ValueKey('create-thread-confirm')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byType(CreateThreadDialog), findsNothing);
    expect(find.text('Active threads'), findsOneWidget);
    expect(find.byKey(const ValueKey('channel-m4')), findsOneWidget);
    expect(find.text('Release follow-up'), findsWidgets);
  });

  testWidgets('keeps validation, loading, and server errors in the dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final result = Completer<bool>();
    String? submittedName;
    int? submittedDuration;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              key: const ValueKey('open-thread-dialog'),
              onPressed: () => unawaited(
                CreateThreadDialog.show(
                  context,
                  onCreate: (name, duration) {
                    submittedName = name;
                    submittedDuration = duration;
                    return result.future;
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-thread-dialog')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-thread-confirm')));
    await tester.pump();
    expect(find.text('Enter a thread name.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('thread-name')),
      'Long-running review',
    );
    await tester.tap(find.text('1 week'));
    await tester.tap(find.byKey(const ValueKey('create-thread-confirm')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(submittedName, 'Long-running review');
    expect(submittedDuration, 10080);

    result.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Could not create the thread.'), findsOneWidget);
    final dialogRect = tester.getRect(find.byType(CreateThreadDialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(500));
    expect(dialogRect.bottom, lessThanOrEqualTo(600));
  });
}
