import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../domain/voice_message_recorder.dart';
import '../../theme/flucord_type.dart';
import 'motion_scope.dart';
import 'native_voice_message_player.dart'
    show VoiceWaveformSurface, formatVoiceDuration;

/// The levels of the recording in progress, one per 20 ms frame.
///
/// Only the live waveform and the clock read it, so a new level redraws them
/// and nothing else.
final class VoiceRecordingLevels extends ChangeNotifier {
  final List<double> _levels = [];
  Duration _duration = Duration.zero;

  List<double> get levels => UnmodifiableListView(_levels);
  Duration get duration => _duration;

  void add(VoiceMessageRecordingProgress frame) {
    _levels.add(frame.level);
    _duration = frame.duration;
    notifyListeners();
  }

  void clear() {
    if (_levels.isEmpty && _duration == Duration.zero) return;
    _levels.clear();
    _duration = Duration.zero;
    notifyListeners();
  }
}

/// The recorded time, as the clock next to the waveform shows it.
class VoiceRecordingClock extends StatelessWidget {
  const VoiceRecordingClock({
    required this.levels,
    required this.color,
    super.key,
  });

  final VoiceRecordingLevels levels;
  final Color color;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: levels,
    builder: (context, _) => Text(
      formatVoiceDuration(levels.duration),
      style: TextStyle(
        color: color,
        fontSize: FlucordType.caption,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

/// The live waveform of a recording. Bars enter at the right edge and move
/// left by one bar every [timePerBar], at display rate. Each bar starts low
/// and eases toward its level instead of jumping to it.
class VoiceRecordingWaveform extends StatefulWidget {
  const VoiceRecordingWaveform({
    required this.levels,
    required this.color,
    super.key,
  });

  /// How long one bar stands for: five 20 ms frames.
  static const timePerBar = Duration(milliseconds: 100);

  /// The distance between two bar centres.
  static const barPitch = 4.0;

  final VoiceRecordingLevels levels;
  final Color color;

  @override
  State<VoiceRecordingWaveform> createState() => _VoiceRecordingWaveformState();
}

class _VoiceRecordingWaveformState extends State<VoiceRecordingWaveform>
    with SingleTickerProviderStateMixin {
  final _WaveformMotion _motion = _WaveformMotion();
  late final Ticker _ticker = createTicker(
    (elapsed) => _motion.advance(_startedAt + elapsed, widget.levels.levels),
  );

  /// The recording's length when the waveform first moved, and where the
  /// waveform's time stood when its ticker last started. A ticker counts
  /// from zero again after a stop, so the bars pick up where the recording
  /// is rather than where they stopped.
  Duration? _origin;
  Duration _startedAt = Duration.zero;

  /// Under the motion rule; otherwise the bars stand still and only grow.
  bool _moves = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _moves = MotionScope.allows(context);
    if (_moves && !_ticker.isActive) {
      final origin = _origin ??= widget.levels.duration;
      _startedAt = widget.levels.duration - origin;
      _ticker.start();
    } else if (!_moves && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const label = 'Live voice recording waveform';
    if (!_moves) {
      return ListenableBuilder(
        listenable: widget.levels,
        builder: (context, _) => VoiceWaveformSurface(
          samples: widget.levels.levels,
          activeColor: widget.color,
          semanticsLabel: label,
        ),
      );
    }
    return Semantics(
      label: label,
      child: SizedBox(
        height: 36,
        child: CustomPaint(
          size: Size.infinite,
          painter: _LiveWaveformPainter(_motion, widget.color),
        ),
      ),
    );
  }
}

/// Where the waveform stands at the current frame: the time on screen and the
/// eased height of the bars still moving.
final class _WaveformMotion extends ChangeNotifier {
  /// How fast a bar closes in on its level. After this long it has covered
  /// about two thirds of the way.
  static const _easing = Duration(milliseconds: 60);

  static const _framesPerBar = 5;

  Duration _elapsed = Duration.zero;
  List<double> _levels = const [];

  /// The bars still on their way to their level. A new bar starts at zero.
  final Map<int, double> _heights = {};

  Duration get elapsed => _elapsed;

  int get newestBar =>
      _elapsed.inMicroseconds ~/
      VoiceRecordingWaveform.timePerBar.inMicroseconds;

  void advance(Duration now, List<double> levels) {
    final step = (now - _elapsed).inMicroseconds;
    _elapsed = now;
    _levels = levels;
    final newest = newestBar;
    _heights.putIfAbsent(newest, () => 0);
    final blend = 1 - math.exp(-step / _easing.inMicroseconds);
    _heights.updateAll(
      (bar, height) => height + (_target(bar) - height) * blend,
    );
    _heights.removeWhere(
      (bar, height) => bar != newest && (_target(bar) - height).abs() < 0.005,
    );
    notifyListeners();
  }

  double heightOf(int bar) => _heights[bar] ?? _target(bar);

  /// The loudest frame of [bar]. A bar whose frames have not arrived yet
  /// follows the latest level.
  double _target(int bar) {
    final start = bar * _framesPerBar;
    if (start >= _levels.length) return _levels.isEmpty ? 0 : _levels.last;
    final end = math.min(start + _framesPerBar, _levels.length);
    return _levels.sublist(start, end).reduce(math.max);
  }
}

final class _LiveWaveformPainter extends CustomPainter {
  _LiveWaveformPainter(this._motion, this._color) : super(repaint: _motion);

  final _WaveformMotion _motion;
  final Color _color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const pitch = VoiceRecordingWaveform.barPitch;
    final barTime = VoiceRecordingWaveform.timePerBar.inMicroseconds;
    final elapsed = _motion.elapsed.inMicroseconds;
    final newest = _motion.newestBar;
    final visible = (size.width / pitch).ceil() + 1;
    final paint = Paint()
      ..color = _color
      ..strokeWidth = pitch * 0.6
      ..strokeCap = StrokeCap.round;
    for (var bar = newest; bar >= 0 && bar > newest - visible; bar--) {
      final age = (elapsed - bar * barTime) / barTime;
      final x = size.width - pitch / 2 - age * pitch;
      final level = _motion.heightOf(bar).clamp(0.08, 1.0);
      final height = math.max(4.0, size.height * level);
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LiveWaveformPainter oldDelegate) =>
      oldDelegate._motion != _motion || oldDelegate._color != _color;
}
