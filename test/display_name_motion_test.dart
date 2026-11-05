import 'dart:ui' as ui;

import 'package:flucord/src/data/discord/display_name_fonts.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/widgets/display_name.dart';
import 'package:flucord/src/presentation/widgets/motion_scope.dart';
import 'package:flucord/src/presentation/widgets/name_style_scope.dart';
import 'package:flucord/src/presentation/widgets/nameplate_motion.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flucord/src/theme/flucord_type.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _gradient = 2;
const _neon = 3;
const _toon = 4;
const _pop = 5;
const _glow = 6;
const _prism = 7;

final class _NoVideos implements NameplateVideos {
  @override
  NameplateVideo open(String url) => throw UnimplementedError();
}

/// A name with [effect] in the colours red and blue, in a scope that has the
/// clock, and in a hover region when [onHover] is set.
Future<void> _pumpName(
  WidgetTester tester,
  int effect, {
  bool onHover = false,
  bool reducedMotion = false,
  bool lookedAt = true,
}) async {
  final name = DisplayName(
    'Freez',
    style: FlucordTextRole.label.style.copyWith(color: Colors.white),
    nameStyle: NameStyle(
      colors: const [0xffff0000, 0xff0000ff],
      effectId: effect,
    ),
    animatesOnHover: onHover,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      builder: (context, child) => TickerMode(
        enabled: lookedAt,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: NameStyleScope(
          videos: _NoVideos(),
          fonts: DisplayNameFonts(load: (_) => throw StateError('no fonts')),
          child: Center(
            child: MotionHoverRegion(
              child: SizedBox(
                key: const ValueKey('row'),
                width: 200,
                child: RepaintBoundary(
                  key: const ValueKey('name'),
                  // Room for what an effect draws outside the letters.
                  child: Padding(padding: const EdgeInsets.all(8), child: name),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Lets the first frames of the app itself end.
  await tester.pump(const Duration(seconds: 1));
}

/// Whether the name draws differently a little later.
Future<bool> _moves(WidgetTester tester) async {
  final before = await _picture(tester);
  await tester.pump(const Duration(milliseconds: 700));
  return !listEquals(before, await _picture(tester));
}

/// The name as drawn, pixel by pixel.
Future<List<int>> _picture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('name')),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
  });
  return bytes!.buffer.asUint8List();
}

void main() {
  for (final (effect, name) in [
    (_gradient, 'gradient'),
    (_glow, 'glow'),
    (_prism, 'prism'),
    (_neon, 'neon'),
    (_toon, 'toon'),
    (_pop, 'pop'),
  ]) {
    testWidgets('a $name name moves in a list', (tester) async {
      await _pumpName(tester, effect);

      expect(await _moves(tester), isTrue);
    });
  }

  testWidgets('a glow name draws as a gradient', (tester) async {
    await _pumpName(tester, _glow);

    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('a name in chat moves only while its message is hovered', (
    tester,
  ) async {
    await _pumpName(tester, _gradient, onHover: true);
    expect(tester.binding.hasScheduledFrame, isFalse);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('row'))));
    await tester.pump();
    expect(await _moves(tester), isTrue);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    // The frame asked for before the pointer left still runs, and no more.
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion keeps a name still', (tester) async {
    await _pumpName(tester, _gradient, reducedMotion: true);

    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(await _moves(tester), isFalse);
  });

  testWidgets('a window nobody looks at keeps a name still', (tester) async {
    await _pumpName(tester, _gradient, lookedAt: false);

    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(await _moves(tester), isFalse);
  });
}
