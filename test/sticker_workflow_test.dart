import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';

void main() {
  testWidgets('searches and sends a native guild sticker from the composer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FlucordApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-sticker-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sticker-search')),
      'native',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sticker-option-forge-signal')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-stickers')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('message-sticker-forge-signal')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sticker-picker')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
