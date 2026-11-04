import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Presses Tab until the keyboard focus sits on or inside [target], the way
/// somebody without a mouse reaches it. Fails when it never gets there.
Future<void> tabTo(
  WidgetTester tester,
  Finder target, {
  int maxPresses = 100,
}) async {
  for (var press = 0; press < maxPresses; press++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (holdsFocus(target)) return;
  }
  fail('Tab never reached $target');
}

/// Whether the keyboard focus is on [target] or on something inside it.
bool holdsFocus(Finder target) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  final targets = target.evaluate().toSet();
  if (targets.contains(focused)) return true;
  var found = false;
  focused.visitAncestorElements((element) {
    found = targets.contains(element);
    return !found;
  });
  return found;
}
