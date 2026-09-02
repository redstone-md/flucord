/// Decides, frame by frame, whether the microphone is carrying speech.
///
/// The threshold is not fixed: it sits [margin] dB above the noise floor, and
/// the floor is the quietest frame of the last [floorWindow] frames. Speech
/// has pauses between syllables and words far below its peaks, so a few
/// seconds of talking leave the floor where the room is; a fan or a keyboard
/// that is always there becomes the floor and stops opening the gate. This is
/// what Discord's "automatically determine input sensitivity" does; a manual
/// sensitivity, when wanted, is a fixed threshold in place of floor + margin.
///
/// Levels are RMS in dB relative to full scale. Once open, the gate stays
/// open for [hangoverFrames] quiet frames: a word's tail and the pause
/// between two.
final class VoiceActivityGate {
  VoiceActivityGate({
    this.margin = 10,
    this.minThreshold = -65,
    this.maxThreshold = -30,
    this.hangoverFrames = defaultHangoverFrames,
    this.floorWindow = 150,
  });

  /// 400 ms of 20 ms frames.
  static const int defaultHangoverFrames = 20;

  /// Where the floor is assumed to be before anything has been heard: a quiet
  /// room with a decent microphone.
  static const double _initialFloor = -60;

  /// Digital silence is minus infinity; the floor is not allowed to chase it.
  static const double _quietest = -90;

  final double margin;
  final double minThreshold;
  final double maxThreshold;
  final int hangoverFrames;
  final int floorWindow;

  final List<double> _recent = [];
  int _next = 0;
  bool _open = false;
  int _quietFrames = 0;

  bool get isOpen => _open;

  /// The quietest level heard lately.
  double get floor => _recent.isEmpty ? _initialFloor : _recent.reduce(_min);

  /// The level a frame has to reach to count as speech.
  double get threshold => (floor + margin).clamp(minThreshold, maxThreshold);

  /// Whether a frame at [dbfs] is speech, or the tail of some.
  bool accept(double dbfs) {
    final level = dbfs < _quietest ? _quietest : dbfs;
    if (level >= threshold) {
      _quietFrames = 0;
      _open = true;
    } else if (_open && ++_quietFrames > hangoverFrames) {
      _open = false;
    }
    _remember(level);
    return _open;
  }

  /// Forgets the floor and closes the gate: for a new device, or a filter
  /// switched on or off, which change what quiet sounds like.
  void reset() {
    _recent.clear();
    _next = 0;
    _open = false;
    _quietFrames = 0;
  }

  void _remember(double level) {
    if (_recent.length < floorWindow) {
      _recent.add(level);
      return;
    }
    _recent[_next] = level;
    _next = (_next + 1) % floorWindow;
  }

  static double _min(double a, double b) => a < b ? a : b;
}
