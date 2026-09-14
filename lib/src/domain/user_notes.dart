/// A private note this account keeps on somebody else.
///
/// Notes are account state, not local state: they live on Discord's servers,
/// follow the account between machines, and survive a restart the way the
/// settings blobs do. The preloaded and frecency blobs carry no notes group,
/// so the store reads and writes the account's own note routes and follows
/// the same dispatch the official client does.
library;

/// The most characters one note may carry, Discord's own limit.
const int userNoteMaxLength = 256;

/// The most notes one account may hold, Discord's own limit.
const int userNoteMaxEntries = 1500;

/// Every note the account holds, keyed by the user each note is about.
final class UserNotes {
  const UserNotes({Map<String, String>? byUserId})
    : _byUserId = byUserId ?? const {};

  final Map<String, String> _byUserId;

  static const empty = UserNotes();

  bool get isEmpty => _byUserId.isEmpty;

  /// How many notes the account holds.
  int get length => _byUserId.length;

  /// The note kept on [userId], or null when there is none.
  String? noteFor(String userId) => _byUserId[userId];

  /// The notes with [userId]'s entry set to [note], or removed from them when
  /// [note] is null or empty.
  UserNotes withNote(String userId, String? note) {
    final kept = Map<String, String>.of(_byUserId);
    if (note == null || note.isEmpty) {
      kept.remove(userId);
    } else {
      kept[userId] = note;
    }
    return UserNotes(byUserId: kept);
  }

  @override
  bool operator ==(Object other) =>
      other is UserNotes && _mapEquals(other._byUserId);

  @override
  int get hashCode => Object.hashAllUnordered(_byUserId.entries);

  bool _mapEquals(Map<String, String> other) {
    if (other.length != _byUserId.length) return false;
    for (final entry in _byUserId.entries) {
      if (other[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Where the account's notes are read from and written back to.
///
/// Every write answers whether it was taken. A refusal is not an error: the
/// account holds the maximum number of notes and Discord refused one more,
/// which the popover has to be able to say in words rather than report as a
/// broken session.
abstract interface class UserNotesRepository {
  /// What is held right now. Empty rather than null before the first load, so
  /// a popover can draw before the notes have arrived.
  UserNotes get current;

  /// Whether the whole map has arrived, which is what makes writes safe: a
  /// note written against an unfetched store would be one entry pretending to
  /// be the whole map.
  bool get isLoaded;

  Stream<UserNotes> get updates;

  /// Fetches the whole map the first time a surface wants it.
  Future<UserNotes> load();

  /// Sets the note on [userId], or removes it when [note] is null or empty.
  ///
  /// True when taken, false when refused. The note is already installed in
  /// [current] by the time this answers, and a refusal puts it back the way
  /// the server still has it.
  Future<bool> setNote({required String userId, required String? note});
}
