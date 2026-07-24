import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';

void main() {
  testWidgets('forwards a message and navigates to the destination channel', (
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
    await tester.tap(find.byKey(const ValueKey('forward-message-m4')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('message-forward-dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('message-forward-forge-native')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('message-forward-submit')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-forward-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('forwarded-message')), findsOneWidget);
    expect(
      find.textContaining('Ship the vertical slice first'),
      findsOneWidget,
    );
    expect(find.textContaining('#general'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
