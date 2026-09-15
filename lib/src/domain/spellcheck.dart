/// A local dictionary the composer asks about the words it is holding.
///
/// Purely a presentation concern: nothing is sent anywhere, and the service
/// is consulted about text somebody is still typing. The contract is small
/// on purpose because the only question worth asking is "is this word one
/// this machine's dictionary knows".
abstract interface class SpellDictionary {
  /// Whether [word] is known, judged against the dictionary's own casing
  /// rules. A word the dictionary has never heard of is reported as unknown
  /// rather than wrong: the answer drives an underline, not a verdict.
  bool knows(String word);
}
