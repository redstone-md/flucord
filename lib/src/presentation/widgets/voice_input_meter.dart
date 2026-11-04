import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/microphone_level_source.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';

/// The microphone's live level on one bar, with the input sensitivity as a
/// mark to drag along it, the way Discord draws it.
///
/// The bar draws [floor] to [ceiling] dB, a wider span than the threshold
/// may take: speech sits around the middle and room noise near the start,
/// so the level reads the same whatever limits the gate has.
///
/// With no [threshold] the gate is automatic: the bar shows the level only.
/// With one, the level is the warning colour below the mark and the success
/// colour past it, so it is plain which sounds open the microphone. The mark
/// takes a drag, a tap on the bar, or the arrow keys, one decibel a step.
///
/// The bar listens to [source] while it is on screen, and that is what holds
/// the microphone open.
class VoiceInputMeter extends StatefulWidget {
  const VoiceInputMeter({
    required this.source,
    required this.minThreshold,
    required this.maxThreshold,
    required this.onThresholdChanged,
    this.threshold,
    super.key,
  });

  final MicrophoneLevelSource source;

  /// The bar's two ends, in dB relative to full scale.
  static const double floor = -80;
  static const double ceiling = 0;

  /// The range the mark may move in, in dB relative to full scale.
  final double minThreshold;
  final double maxThreshold;

  /// The level the microphone opens at, or null for the automatic gate.
  final double? threshold;
  final ValueChanged<double> onThresholdChanged;

  @override
  State<VoiceInputMeter> createState() => _VoiceInputMeterState();
}

class _VoiceInputMeterState extends State<VoiceInputMeter> {
  static const double _height = 20;
  static const double _markSize = 14;
  static const double _keyStep = 1;

  StreamSubscription<double>? _subscription;
  double _level = double.negativeInfinity;
  Object? _error;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(VoiceInputMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      unawaited(_subscription?.cancel());
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _listen() {
    _subscription = widget.source.inputLevels.listen(
      (level) => setState(() {
        _level = level;
        _error = null;
      }),
      onError: (Object error) => setState(() => _error = error),
    );
  }

  /// Where [dbfs] falls along the bar, from 0 to 1.
  static double _fraction(double dbfs) => dbfs.isFinite
      ? ((dbfs - VoiceInputMeter.floor) /
                (VoiceInputMeter.ceiling - VoiceInputMeter.floor))
            .clamp(0.0, 1.0)
      : 0;

  double _held(double dbfs) =>
      dbfs.clamp(widget.minThreshold, widget.maxThreshold);

  void _setAt(double x, double width) => widget.onThresholdChanged(
    _held(
      VoiceInputMeter.floor +
          x / width * (VoiceInputMeter.ceiling - VoiceInputMeter.floor),
    ),
  );

  void _step(double threshold, double by) =>
      widget.onThresholdChanged(_held(threshold + by));

  KeyEventResult _handleKey(double threshold, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.arrowUp => _keyStep,
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowDown => -_keyStep,
      _ => null,
    };
    if (step == null) return KeyEventResult.ignored;
    _step(threshold, step);
    return KeyEventResult.handled;
  }

  static String _decibels(double dbfs) => '${dbfs.toStringAsFixed(0)} dB';

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final threshold = widget.threshold;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final bar = CustomPaint(
              key: const ValueKey('voice-input-meter-bar'),
              size: Size(width, _height),
              painter: _LevelPainter(
                level: _fraction(_level),
                mark: threshold == null ? null : _fraction(threshold),
                track: surfaces.quietFill,
                belowMark: surfaces.warning,
                pastMark: surfaces.success,
              ),
            );
            if (threshold == null) {
              return Semantics(label: 'Microphone level', child: bar);
            }
            return _markedBar(
              bar: bar,
              threshold: threshold,
              width: width,
              focusRing: surfaces.focusRing,
            );
          },
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            'The microphone could not be opened: $error',
            style: FlucordTextRole.caption.style.copyWith(
              color: surfaces.errorText,
            ),
          ),
        ],
      ],
    );
  }

  /// The bar with the threshold's mark on it, and everything that moves it.
  Widget _markedBar({
    required Widget bar,
    required double threshold,
    required double width,
    required Color focusRing,
  }) {
    final held = _held(threshold);
    return Semantics(
      slider: true,
      focusable: true,
      focused: _focused,
      label: 'Input sensitivity',
      value: _decibels(held),
      increasedValue: _decibels(_held(held + _keyStep)),
      decreasedValue: _decibels(_held(held - _keyStep)),
      onIncrease: () => _step(held, _keyStep),
      onDecrease: () => _step(held, -_keyStep),
      child: Focus(
        includeSemantics: false,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) => _handleKey(held, event),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Increase and decrease say all a pointer can do here.
            excludeFromSemantics: true,
            onTapDown: (details) => _setAt(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                _setAt(details.localPosition.dx, width),
            child: Stack(
              // The mark is centred on the threshold: at a limit on the
              // bar's end, half of it hangs past, as Discord's does.
              clipBehavior: Clip.none,
              children: [
                bar,
                Positioned(
                  left: _fraction(held) * width - _markSize / 2,
                  top: (_height - _markSize) / 2,
                  child: Tooltip(
                    message: _decibels(held),
                    excludeFromSemantics: true,
                    child: _Mark(focused: _focused, focusRing: focusRing),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The white disc at the threshold, ringed while it has the keyboard.
class _Mark extends StatelessWidget {
  const _Mark({required this.focused, required this.focusRing});

  final bool focused;
  final Color focusRing;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    key: const ValueKey('voice-input-meter-mark'),
    dimension: _VoiceInputMeterState._markSize,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: FlucordFixedColors.onFill,
        shape: BoxShape.circle,
        border: focused
            ? Border.all(
                color: focusRing,
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
      ),
    ),
  );
}

/// The level over its track, split at the mark when there is one.
class _LevelPainter extends CustomPainter {
  const _LevelPainter({
    required this.level,
    required this.mark,
    required this.track,
    required this.belowMark,
    required this.pastMark,
  });

  static const double _barHeight = 6;

  /// How far along the bar the level and the mark are, from 0 to 1.
  final double level;
  final double? mark;
  final Color track;
  final Color belowMark;
  final Color pastMark;

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - _barHeight) / 2;
    final bottom = top + _barHeight;
    canvas.drawRRect(
      FlucordRadius.full.toRRect(Rect.fromLTRB(0, top, size.width, bottom)),
      Paint()..color = track,
    );
    final levelEnd = level * size.width;
    if (levelEnd <= 0) return;
    // Automatic sensitivity has no mark: the whole level is past it.
    final split = math.min((mark ?? 0) * size.width, levelEnd);
    canvas
      ..save()
      ..clipRRect(
        FlucordRadius.full.toRRect(Rect.fromLTRB(0, top, levelEnd, bottom)),
      );
    if (split > 0) {
      canvas.drawRect(
        Rect.fromLTRB(0, top, split, bottom),
        Paint()..color = belowMark,
      );
    }
    if (levelEnd > split) {
      canvas.drawRect(
        Rect.fromLTRB(split, top, levelEnd, bottom),
        Paint()..color = pastMark,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LevelPainter old) =>
      old.level != level ||
      old.mark != mark ||
      old.track != track ||
      old.belowMark != belowMark ||
      old.pastMark != pastMark;
}
