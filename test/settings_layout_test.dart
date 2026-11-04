import 'package:flucord/src/presentation/widgets/settings_layout.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the close button sits as far from the top as from the side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const close = ValueKey('close');
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: const SettingsLayout(
          groups: [],
          title: 'Voice & Video',
          closeKey: close,
          body: SizedBox.shrink(),
        ),
      ),
    );

    final surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;
    final card = tester.getRect(
      find.ancestor(
        of: find.byKey(close),
        matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.color == surfaces.canvas,
        ),
      ),
    );
    final button = tester.getRect(find.byKey(close));

    expect(button.size, const Size.square(28));
    expect(button.top - card.top, 16);
    expect(card.right - button.right, 16);
    // The hint stays centred under the button.
    expect(tester.getCenter(find.text('Esc')).dx, button.center.dx);
  });

  testWidgets('a large text size moves the body down, under the Esc hint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const body = ValueKey('body');
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1280, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: const SettingsLayout(
            groups: [],
            title: 'Voice & Video',
            body: SizedBox.expand(key: body),
          ),
        ),
      ),
    );

    expect(
      tester.getRect(find.text('Esc')).bottom,
      lessThanOrEqualTo(tester.getRect(find.byKey(body)).top),
    );
  });
}
