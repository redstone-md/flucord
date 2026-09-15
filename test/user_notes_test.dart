import 'package:flucord/src/data/discord/discord_user_notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an account with no notes loads as an empty map', () async {
    final repository = DiscordUserNotesRepository(_FakeTransport());
    addTearDown(repository.close);

    final notes = await repository.load();

    expect(notes.isEmpty, isTrue);
    expect(notes.noteFor('222'), isNull);
    expect(repository.isLoaded, isTrue);
  });

  test('READY seeds the map the account already holds', () async {
    final repository = DiscordUserNotesRepository(_FakeTransport());
    addTearDown(repository.close);

    repository.acceptGatewayDispatch('READY', const {
      'notes': {'222': 'met at the offsite', '333': ''},
    });

    expect(repository.current.noteFor('222'), 'met at the offsite');
    // An empty note is no note, which is how Discord spells a cleared one.
    expect(repository.current.noteFor('333'), isNull);
    // READY means no request is spent on the read.
    expect(repository.isLoaded, isTrue);
  });

  test('a note can be added, edited, and removed over the transport', () async {
    final transport = _FakeTransport()..stored = {'222': 'met at the offsite'};
    final repository = DiscordUserNotesRepository(transport);
    addTearDown(repository.close);

    await repository.load();
    expect(
      await repository.setNote(userId: '222', note: 'sends the digest'),
      isTrue,
    );
    expect(transport.writes.single, ('222', 'sends the digest'));

    expect(
      await repository.setNote(userId: '222', note: 'moved servers'),
      isTrue,
    );
    expect(transport.writes.last, ('222', 'moved servers'));

    expect(await repository.setNote(userId: '222', note: ''), isTrue);
    expect(transport.writes.last, ('222', null));
    expect(repository.current.noteFor('222'), isNull);
  });

  test('a refused write rolls the optimistic note back', () async {
    final transport = _FakeTransport()
      ..stored = {}
      ..refuse = true;
    final repository = DiscordUserNotesRepository(transport);
    addTearDown(repository.close);

    await repository.load();
    final taken = await repository.setNote(userId: '222', note: 'too many');

    expect(taken, isFalse);
    expect(repository.current.noteFor('222'), isNull);
  });

  test('a note longer than the limit is trimmed before it is sent', () async {
    final transport = _FakeTransport()..stored = {};
    final repository = DiscordUserNotesRepository(transport);
    addTearDown(repository.close);

    await repository.load();
    await repository.setNote(userId: '222', note: 'x' * 300);

    expect(transport.writes.single.$2?.length, 256);
    expect(repository.current.noteFor('222')?.length, 256);
  });

  test('USER_NOTE_UPDATE revises one entry', () async {
    final repository = DiscordUserNotesRepository(_FakeTransport());
    addTearDown(repository.close);

    repository.acceptGatewayDispatch('READY', const {
      'notes': {'222': 'met at the offsite'},
    });
    repository.acceptGatewayDispatch('USER_NOTE_UPDATE', const {
      'id': '222',
      'note': 'moved servers',
    });
    expect(repository.current.noteFor('222'), 'moved servers');

    // A cleared note arrives as null or empty, and reads as removed.
    repository.acceptGatewayDispatch('USER_NOTE_UPDATE', const {
      'id': '222',
      'note': null,
    });
    expect(repository.current.noteFor('222'), isNull);
  });

  test('a note revision before the map is held rather than installed', () {
    final repository = DiscordUserNotesRepository(_FakeTransport());
    addTearDown(repository.close);

    repository.acceptGatewayDispatch('USER_NOTE_UPDATE', const {
      'id': '222',
      'note': 'moved servers',
    });

    // One entry is not the account's whole map, so the store stays unloaded
    // and the load still happens.
    expect(repository.isLoaded, isFalse);
    expect(repository.current.noteFor('222'), isNull);
  });

  test('a dispatch for another event leaves the map alone', () async {
    final repository = DiscordUserNotesRepository(_FakeTransport());
    addTearDown(repository.close);

    repository.acceptGatewayDispatch('READY', const {
      'notes': {'222': 'met at the offsite'},
    });
    repository.acceptGatewayDispatch('MESSAGE_CREATE', const {
      'id': '222',
      'note': 'ignored',
    });

    expect(repository.current.noteFor('222'), 'met at the offsite');
  });

  test('the map survives a restart', () async {
    // Notes are account state: a restart is a new store reading the same
    // transport, and what the account still holds is what it shows.
    final transport = _FakeTransport()..stored = {'222': 'met at the offsite'};
    final first = DiscordUserNotesRepository(transport);
    await first.load();
    await first.setNote(userId: '222', note: 'sends the digest');
    await first.close();

    final restarted = DiscordUserNotesRepository(transport);
    addTearDown(restarted.close);
    final notes = await restarted.load();

    expect(notes.noteFor('222'), 'sends the digest');
  });

  test('a failed read leaves an empty, still-usable map', () async {
    final transport = _FakeTransport()..failReads = true;
    final repository = DiscordUserNotesRepository(transport);
    addTearDown(repository.close);

    final notes = await repository.load();

    expect(notes.isEmpty, isTrue);
    expect(repository.isLoaded, isTrue);
  });
}

final class _FakeTransport implements DiscordUserNotesTransport {
  Map<String, String> stored = {};
  final List<(String, String?)> writes = [];
  bool refuse = false;
  bool failReads = false;

  @override
  Future<Map<String, Object?>> readNotes() async {
    if (failReads) throw StateError('offline');
    return Map<String, Object?>.of(stored);
  }

  @override
  Future<Object?> writeNote({
    required String userId,
    required Map<String, Object?> body,
  }) async {
    if (refuse) return null;
    final note = body['note'];
    if (note is String && note.isNotEmpty) {
      stored[userId] = note;
      writes.add((userId, note));
    } else {
      stored.remove(userId);
      writes.add((userId, null));
    }
    return {};
  }
}
