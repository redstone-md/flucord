import 'dart:async';

import '../../app_log.dart';
import '../../domain/user_notes.dart';

/// The REST surface the note routes offer.
abstract interface class DiscordUserNotesTransport {
  /// `GET /users/@me/notes`, the whole map the account holds.
  Future<Map<String, Object?>> readNotes();

  /// `PUT /users/@me/notes/{userId}`.
  ///
  /// Answers null when Discord refused the write, which the route does when
  /// the note is too long or the account holds the maximum number of them.
  /// Which status codes those are is the transport's business.
  Future<Object?> writeNote({
    required String userId,
    required Map<String, Object?> body,
  });
}

/// The account's notes over the desktop-user transport.
///
/// Writes are optimistic and a refusal re-reads, which mirrors the settings
/// stores: the note is a click-sized edit and waiting for a round trip before
/// showing it would feel broken on a slow link, but the server's map is the
/// only truth, so a refused write is rolled back rather than left on screen.
final class DiscordUserNotesRepository implements UserNotesRepository {
  DiscordUserNotesRepository(this._transport);

  final DiscordUserNotesTransport _transport;
  final StreamController<UserNotes> _updates = StreamController.broadcast();

  UserNotes _current = UserNotes.empty;
  bool _installed = false;
  Future<UserNotes>? _loadInFlight;
  Future<void>? _writeInFlight;

  @override
  UserNotes get current => _current;

  @override
  bool get isLoaded => _installed;

  @override
  Stream<UserNotes> get updates => _updates.stream;

  @override
  Future<UserNotes> load() {
    if (_installed) return Future.value(_current);
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;
    final future = _fetch();
    _loadInFlight = future;
    return future.whenComplete(() => _loadInFlight = null);
  }

  /// Feeds a gateway dispatch to the store.
  ///
  /// `USER_NOTE_UPDATE` is how an edit made on another device reaches this
  /// one; `READY` carries the whole map at login, so a healthy session never
  /// spends a request on the read.
  void acceptGatewayDispatch(String name, Map<String, Object?> data) {
    switch (name) {
      case 'READY':
        _install(_readMap(data['notes']));
      case 'USER_NOTE_UPDATE':
        if (!_installed) {
          // A single revision is not the whole map, and installing it as one
          // would mark the store loaded while holding one entry. READY always
          // arrives first on this socket, so this is unreachable rather than
          // merely unlikely.
          return;
        }
        final id = data['id'];
        if (id is! String || id.isEmpty) return;
        final note = data['note'];
        _install(
          note is String && note.isNotEmpty
              ? _current.withNote(id, note)
              : _current.withNote(id, null),
        );
    }
  }

  @override
  Future<bool> setNote({required String userId, required String? note}) async {
    final held = await _fetched();
    final clamped = note == null || note.isEmpty ? null : _clamped(note);
    final next = held.withNote(userId, clamped);
    if (next == held) return true;
    _install(next);
    final write = _write(userId, clamped ?? '');
    _writeInFlight = write;
    try {
      return await write;
    } finally {
      if (identical(_writeInFlight, write)) _writeInFlight = null;
    }
  }

  Future<void> close() async {
    await _writeInFlight;
    if (!_updates.isClosed) await _updates.close();
  }

  /// The notes, fetching them first if a popover acted before they loaded.
  Future<UserNotes> _fetched() async {
    if (!_installed) await load();
    return _current;
  }

  Future<UserNotes> _fetch() async {
    try {
      final payload = await _transport.readNotes();
      _install(_readMap(payload));
    } on Object catch (error) {
      // The map stays empty, which is what a popover draws before the load.
      _log('Reading notes failed: $error');
      _install(UserNotes.empty);
    }
    return _current;
  }

  Future<bool> _write(String userId, String note) async {
    try {
      final answer = await _transport.writeNote(
        userId: userId,
        body: note.isEmpty ? {'note': null} : {'note': note},
      );
      if (answer == null) {
        // Refused, so the optimistic note is not on the account.
        await _reload();
        return false;
      }
      return true;
    } on Object catch (error) {
      _log('Saving a note failed: $error');
      await _reload();
      return false;
    }
  }

  Future<void> _reload() async {
    try {
      final payload = await _transport.readNotes();
      _install(_readMap(payload));
    } on Object catch (error) {
      _log('Re-reading notes failed: $error');
    }
  }

  void _install(UserNotes notes) {
    _current = notes;
    _installed = true;
    if (!_updates.isClosed) _updates.add(notes);
  }

  static UserNotes _readMap(Object? payload) {
    if (payload is! Map) return UserNotes.empty;
    final notes = <String, String>{};
    payload.cast<String, Object?>().forEach((userId, note) {
      if (userId.isNotEmpty && note is String && note.isNotEmpty) {
        notes[userId] = note;
      }
    });
    return UserNotes(byUserId: notes);
  }

  /// Discord's own limit for a note. Trimming here rather than sending the
  /// refusal-bait keeps the editor honest as the user types.
  static String _clamped(String note) {
    if (note.length <= userNoteMaxLength) return note;
    return note.substring(0, userNoteMaxLength);
  }

  static void _log(String message) => AppLog.warning('discord.notes', message);
}
