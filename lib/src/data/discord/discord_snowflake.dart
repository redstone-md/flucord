/// Snowflake arithmetic the gateway payloads are specified in terms of.
///
/// Discord serialises snowflakes as decimal strings that do not survive a
/// JavaScript number, so its own client never compares them arithmetically: it
/// ships a string comparator and a timestamp extractor, and the ordering rules
/// for read states and the DM list are written against those two primitives.
/// Porting the primitives rather than reaching for `int.parse` keeps every
/// caller on the same semantics, including for the opaque ids Discord mints for
/// placeholder records.
abstract final class DiscordSnowflake {
  /// The first millisecond Discord counts from, in Unix milliseconds.
  static const epochMillis = 1420070400000;

  /// Bits a snowflake reserves below its timestamp.
  static const _timestampShift = 22;

  static const _zeroCodeUnit = 0x30;
  static const _nineCodeUnit = 0x39;

  /// Orders two snowflakes by value: negative when [left] is the older id.
  static int compare(String left, String right) {
    final a = _canonical(left);
    final b = _canonical(right);
    if (a.length != b.length) return a.length.compareTo(b.length);
    return a.compareTo(b);
  }

  /// Unix milliseconds encoded in [snowflake].
  ///
  /// A value that carries no timestamp — an opaque id, or an id of zero —
  /// resolves to Discord's epoch, which ranks it below every real snowflake
  /// instead of aborting an ordering pass.
  static int timestampMillis(String snowflake) =>
      (BigInt.parse(_canonical(snowflake)) >> _timestampShift).toInt() +
      epochMillis;

  /// The lowest snowflake Discord could mint at [millis].
  ///
  /// The DM sort store promotes a message request's timestamp into snowflake
  /// space so it can be compared against `last_message_id`; that promotion is
  /// the only reason this direction of the conversion exists.
  static String fromTimestampMillis(int millis) {
    final offset = millis - epochMillis;
    if (offset <= 0) return '0';
    return (BigInt.from(offset) << _timestampShift).toString();
  }

  /// Strips leading zeroes, mapping anything that is not decimal digits to `0`.
  static String _canonical(String value) {
    var start = 0;
    while (start < value.length && value.codeUnitAt(start) == _zeroCodeUnit) {
      start++;
    }
    for (var index = start; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (unit < _zeroCodeUnit || unit > _nineCodeUnit) return '0';
    }
    return start == value.length ? '0' : value.substring(start);
  }
}
