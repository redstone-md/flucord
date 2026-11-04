/// The first letters of the first two words of [name], as a server tile
/// shows them when it has no icon: "Dota 2" is "D2". A blank name is "?".
String monogramOf(String name) {
  final letters = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => String.fromCharCode(word.runes.first).toUpperCase())
      .join();
  return letters.isEmpty ? '?' : letters;
}

/// The fill behind a monogram for something with no colour of its own, the
/// same for [id] wherever it is drawn.
int monogramColorOf(String id) {
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _monogramColors[hash % _monogramColors.length];
}

const _monogramColors = [
  0xff456b5a,
  0xff765341,
  0xff5f5b76,
  0xff59636a,
  0xff486b70,
  0xff6f5967,
];
