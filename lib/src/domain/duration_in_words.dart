/// [duration] in its largest whole unit, such as "3 minutes" or "1 day".
///
/// The count drops what is left of the unit, as a clock does. With [roundUp],
/// any part of a unit counts as a whole one, for a wait that must not seem to
/// end too early.
String durationInWords(Duration duration, {bool roundUp = false}) {
  final measured = roundUp
      ? Duration(seconds: (duration.inMilliseconds / 1000).ceil())
      : duration;
  final (unit, length) = _units.firstWhere(
    (unit) => measured >= unit.$2,
    orElse: () => _units.last,
  );
  final count = measured.inMilliseconds / length.inMilliseconds;
  final whole = roundUp ? count.ceil() : count.floor();
  return whole == 1 ? '1 $unit' : '$whole ${unit}s';
}

const _units = [
  ('day', Duration(days: 1)),
  ('hour', Duration(hours: 1)),
  ('minute', Duration(minutes: 1)),
  ('second', Duration(seconds: 1)),
];
