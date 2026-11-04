import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flucord/src/domain/voice_message_recorder.dart';
import 'package:flucord/src/presentation/widgets/voice_recording_waveform.dart';

/// One drawn bar: its centre and its height.
typedef _Bar = ({double x, double height});

void main() {
  late VoiceRecordingLevels levels;
  var recorded = Duration.zero;

  setUp(() {
    levels = VoiceRecordingLevels();
    recorded = Duration.zero;
  });
  tearDown(() => levels.dispose());

  void record(int frames, double level) {
    for (var frame = 0; frame < frames; frame++) {
      recorded += const Duration(milliseconds: 20);
      levels.add(
        VoiceMessageRecordingProgress(duration: recorded, level: level),
      );
    }
  }

  Future<void> pumpWaveform(WidgetTester tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            child: VoiceRecordingWaveform(
              key: const ValueKey('waveform'),
              levels: levels,
              color: const Color(0xFFFF0000),
            ),
          ),
        ),
      ),
    );
    // The ticker's first frame, at time zero.
    await tester.pump();
  }

  List<_Bar> bars(WidgetTester tester) {
    final drawn = <_Bar>[];
    expect(
      tester.renderObject(
        find.descendant(
          of: find.byKey(const ValueKey('waveform')),
          matching: find.byType(CustomPaint),
        ),
      ),
      paints..everything((method, arguments) {
        if (method == #drawLine) {
          final top = arguments[0] as Offset;
          final bottom = arguments[1] as Offset;
          drawn.add((x: top.dx, height: bottom.dy - top.dy));
        }
        return true;
      }),
    );
    return drawn;
  }

  List<double> xs(WidgetTester tester) => [
    for (final bar in bars(tester)) bar.x,
  ];

  testWidgets('bars enter at the right and move left one pitch per bar time', (
    tester,
  ) async {
    record(5, 0.5);
    await pumpWaveform(tester);
    expect(xs(tester), [198]);

    await tester.pump(const Duration(milliseconds: 50));
    expect(xs(tester), [196]);

    record(5, 0.5);
    await tester.pump(const Duration(milliseconds: 100));
    expect(xs(tester), [196, 192]);
  });

  testWidgets('a new bar eases toward its level, and older bars settle there', (
    tester,
  ) async {
    await pumpWaveform(tester);
    final heights = <double>[];
    for (var frame = 0; frame < 4; frame++) {
      record(1, 1);
      await tester.pump(const Duration(milliseconds: 16));
      heights.add(bars(tester).first.height);
    }

    expect(heights, orderedEquals([...heights]..sort()));
    expect(heights.first, greaterThan(4));
    expect(heights.last, lessThan(36));

    for (var frame = 0; frame < 25; frame++) {
      record(1, 1);
      await tester.pump(const Duration(milliseconds: 16));
    }
    final settled = [for (final bar in bars(tester).skip(3)) bar.height];
    expect(settled, isNotEmpty);
    expect(settled, everyElement(closeTo(36, 0.5)));
  });
}
