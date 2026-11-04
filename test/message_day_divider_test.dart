import 'package:flucord/src/presentation/widgets/message_day_divider.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a long date in a narrow timeline gives way, not overflows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              // The longest weekday and month there are.
              child: MessageDayDivider(day: DateTime(2026, 9, 30)),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Wednesday'), findsOneWidget);
  });
}
