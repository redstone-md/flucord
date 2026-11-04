import 'dart:async';

import 'package:flucord/src/application/microphone_level_source.dart';
import 'package:flucord/src/presentation/widgets/voice_input_meter.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bar runs from -65 to -30 dB over 350 px: 10 px per dB.
const double _width = 350;
const double _min = -65;
const double _max = -30;
const _meterKey = ValueKey('meter');
const _markKey = ValueKey('voice-input-meter-mark');

void main() {
  late _FakeLevels levels;
  late List<double> changes;

  setUp(() {
    levels = _FakeLevels();
    changes = [];
  });
  tearDown(() => levels.close());

  Future<void> pumpMeter(WidgetTester tester, {double? threshold}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: FlucordTheme.dark,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _width,
                child: VoiceInputMeter(
                  key: _meterKey,
                  source: levels,
                  min: _min,
                  max: _max,
                  threshold: threshold,
                  onThresholdChanged: changes.add,
                ),
              ),
            ),
          ),
        ),
      );

  double barLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(_meterKey)).dx;

  testWidgets('the mark sits at the stored threshold', (tester) async {
    await pumpMeter(tester, threshold: -45);
    expect(tester.getCenter(find.byKey(_markKey)).dx - barLeft(tester), 200);

    await pumpMeter(tester, threshold: -60);
    expect(tester.getCenter(find.byKey(_markKey)).dx - barLeft(tester), 50);
  });

  testWidgets('automatic sensitivity has no mark', (tester) async {
    await pumpMeter(tester);
    expect(find.byKey(_markKey), findsNothing);
  });

  testWidgets('dragging the mark sets the threshold', (tester) async {
    await pumpMeter(tester, threshold: -45);
    await tester.drag(find.byKey(_markKey), const Offset(40, 0));
    expect(changes, isNotEmpty);
    expect(changes.last, closeTo(-41, 0.01));
  });

  testWidgets('the arrow keys move the threshold a decibel at a time', (
    tester,
  ) async {
    await pumpMeter(tester, threshold: -45);
    final focus = Focus.of(tester.element(find.byKey(_markKey)));
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(changes.last, -44);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(changes.last, -46);
  });

  testWidgets('reads as a slider with its value in decibels', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpMeter(tester, threshold: -45);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Input sensitivity')),
      matchesSemantics(
        isSlider: true,
        isFocusable: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        label: 'Input sensitivity',
        value: '-45 dB',
        increasedValue: '-44 dB',
        decreasedValue: '-46 dB',
      ),
    );
    semantics.dispose();
  });

  testWidgets('the level is the warning colour up to the mark and the '
      'success colour past it', (tester) async {
    await pumpMeter(tester, threshold: -45);
    levels.add(-35);
    await tester.pump();

    final surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;
    expect(
      tester.renderObject(find.byKey(const ValueKey('voice-input-meter-bar'))),
      paints
        ..rect(
          rect: const Rect.fromLTRB(0, 7, 200, 13),
          color: surfaces.warning,
        )
        ..rect(
          rect: const Rect.fromLTRB(200, 7, 300, 13),
          color: surfaces.success,
        ),
    );
  });

  testWidgets('a level under the mark is all the warning colour', (
    tester,
  ) async {
    await pumpMeter(tester, threshold: -45);
    levels.add(-55);
    await tester.pump();

    final surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;
    final bar = tester.renderObject(
      find.byKey(const ValueKey('voice-input-meter-bar')),
    );
    expect(
      bar,
      paints..rect(
        rect: const Rect.fromLTRB(0, 7, 100, 13),
        color: surfaces.warning,
      ),
    );
    expect(bar, isNot(paints..rect(color: surfaces.success)));
  });

  testWidgets('with automatic sensitivity the level is all the success '
      'colour', (tester) async {
    await pumpMeter(tester);
    levels.add(-55);
    await tester.pump();

    final surfaces = FlucordTheme.dark.extension<FlucordSurfaceTheme>()!;
    final bar = tester.renderObject(
      find.byKey(const ValueKey('voice-input-meter-bar')),
    );
    expect(
      bar,
      paints..rect(
        rect: const Rect.fromLTRB(0, 7, 100, 13),
        color: surfaces.success,
      ),
    );
    expect(bar, isNot(paints..rect(color: surfaces.warning)));
  });

  testWidgets('a microphone that will not open says why', (tester) async {
    await pumpMeter(tester);
    levels.addError(StateError('no capture device'));
    await tester.pump();

    expect(
      find.textContaining('The microphone could not be opened'),
      findsOneWidget,
    );
  });

  testWidgets('stops listening when it leaves the screen', (tester) async {
    await pumpMeter(tester);
    expect(levels.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(levels.hasListener, isFalse);
  });
}

final class _FakeLevels implements MicrophoneLevelSource {
  final StreamController<double> _levels = StreamController.broadcast();

  bool get hasListener => _levels.hasListener;

  void add(double dbfs) => _levels.add(dbfs);

  void addError(Object error) => _levels.addError(error);

  Future<void> close() => _levels.close();

  @override
  Stream<double> get inputLevels => _levels.stream;
}
