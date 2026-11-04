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
