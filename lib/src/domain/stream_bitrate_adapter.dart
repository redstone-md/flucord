import 'dart:math';

/// Follows the loss the far end reports with the share's bitrate.
///
/// A share is sent at the bitrate the settings say, and an uplink that
/// cannot carry it drops packets rather than saying so. Each receiver report
/// says what fraction was lost; the rule is WebRTC's loss-based one, in
/// short: back off in proportion to heavy loss, creep back up while the
/// path is clean, hold in between. Never above the target, never below a
/// floor that still carries a picture.
final class StreamBitrateAdapter {
  StreamBitrateAdapter({required int target})
    : _target = target,
      _bitrate = target;

  /// Loss above this backs the bitrate off.
  static const lossToBackOff = 0.10;

  /// Loss below this lets it recover.
  static const lossToRecover = 0.02;

  /// How much a clean report recovers, as a factor.
  static const recoverStep = 1.08;

  /// The lowest the bitrate goes, as a fraction of the target.
  static const floorRatio = 0.2;

  int _target;
  int _bitrate;

  /// Points the adapter at a new target, keeping the same fraction of it:
  /// the loss the link reported still holds, and a settings change is no
  /// reason to relearn it.
  void retarget(int target) {
    _bitrate = (_bitrate / _target * target).round();
    _target = target;
  }

  int get target => _target;

  int get bitrate => _bitrate;

  bool get isAdapted => _bitrate != _target;

  /// Takes one receiver report, answering the new bitrate when it changed.
  int? report(double lossRatio) {
    final was = _bitrate;
    if (lossRatio > lossToBackOff) {
      _bitrate = max(
        (_target * floorRatio).round(),
        (_bitrate * (1 - 0.5 * lossRatio)).round(),
      );
    } else if (lossRatio < lossToRecover) {
      _bitrate = min(_target, (_bitrate * recoverStep).round());
    }
    return _bitrate == was ? null : _bitrate;
  }
}
