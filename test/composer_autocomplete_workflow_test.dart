import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';

void main() {
  testWidgets('resolves a workspace member from the live composer catalog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FlucordApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final composer = find.byKey(const ValueKey('message-composer'));
    await tester.enterText(composer, '@mi');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('composer-suggestion-member-mira')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(tester.widget<TextField>(composer).controller!.text, '<@mira> ');
    expect(find.byKey(const ValueKey('composer-autocomplete')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
