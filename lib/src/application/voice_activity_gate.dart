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

  /// The threshold chosen by hand, when one was. Null is the automatic gate:
  /// floor plus margin.
  double? _manualThreshold;

  final List<double> _recent = [];
  int _next = 0;
  bool _open = false;
  int _quietFrames = 0;

  bool get isOpen => _open;

  /// The quietest level heard lately.
  double get floor => _recent.isEmpty ? _initialFloor : _recent.reduce(_min);

  /// The level a frame has to reach to count as speech.
  ///
  /// A threshold set by hand is returned as it was given, clamped to the same
  /// range the automatic one is: a number past the range describes a machine
  /// that cannot exist.
  double get threshold =>
      _manualThreshold?.clamp(minThreshold, maxThreshold) ??
      (floor + margin).clamp(minThreshold, maxThreshold);

  /// Whether the gate follows the room's noise floor rather than a threshold
  /// chosen by hand.
  bool get isAutomatic => _manualThreshold == null;

  /// Sets the level a frame has to reach to count as speech, in dB relative
  /// to full scale, or returns to the automatic floor-plus-margin gate with
  /// null.
  ///
  /// The floor keeps being learned while a manual threshold is in force, so
  /// switching back to automatic starts from an honest floor rather than
  /// one the window stopped hearing. The gate is not reset: a threshold
  /// changed mid-speech is judged on the next frame, like every other.
  void setManualThreshold(double? dbfs) {
    _manualThreshold = dbfs;
  }

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
