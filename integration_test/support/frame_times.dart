import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// In profile mode the engine hands over its frame timings about every 100 ms.
/// Waiting this long lets frames from before a recording drain away, and lets
/// the last frames of the recording arrive.
const _timingsDrain = Duration(milliseconds: 500);

/// Runs [action] and returns the times of the frames the engine drew during it,
/// ready to encode as JSON. All times are in milliseconds.
///
/// `total` runs from the vsync signal to the end of raster. It is the one to
/// read first, because it also holds the time a frame waited for the UI thread.
/// A gateway event handled between frames shows only there, not under `build`.
Future<Map<String, Object>> recordFrames(Future<void> Function() action) async {
  await Future<void>.delayed(_timingsDrain);
  final frames = <FrameTiming>[];
  void collect(List<FrameTiming> batch) => frames.addAll(batch);
  final binding = SchedulerBinding.instance;
  binding.addTimingsCallback(collect);
  try {
    await action();
    await Future<void>.delayed(_timingsDrain);
  } finally {
    binding.removeTimingsCallback(collect);
  }
  if (frames.isEmpty) fail('The engine reported no frames.');
  return {
    'frames': frames.length,
    'build': _summary(frames.map((frame) => frame.buildDuration)),
    'raster': _summary(frames.map((frame) => frame.rasterDuration)),
    'total': _summary(frames.map((frame) => frame.totalSpan)),
  };
}

Map<String, double> _summary(Iterable<Duration> durations) {
  final sorted = durations.toList()..sort();
  double milliseconds(Duration duration) => duration.inMicroseconds / 1000;
  // Nearest rank: the smallest time that at least this share of frames meet.
  double percentile(double share) =>
      milliseconds(sorted[(share * sorted.length).ceil() - 1]);
  return {
    'p50': percentile(0.50),
    'p95': percentile(0.95),
    'p99': percentile(0.99),
    'max': milliseconds(sorted.last),
  };
}
