import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/member_profile_controller.dart';
import 'package:flucord/src/domain/user_notes.dart';
import 'package:flucord/src/domain/user_profile.dart';

void main() {
  group('fetch and render', () {
    test('opening a member fetches the profile and the note', () async {
      final profile = _FakeProfileRepository();
      final notes = _FakeNotesRepository()
        ..held = {'222': 'met at the offsite'};
      final controller = MemberProfileController(
        profileProvider: () => profile,
        notesProvider: () => notes,
      );
      addTearDown(controller.dispose);

      await controller.open('222');

      expect(profile.requestedIds, ['222']);
      expect(controller.profile?.bio, 'ships the parser');
      // The note is what the account already holds, not what the fetch said.
      expect(controller.note, 'met at the offsite');
      expect(controller.error, isNull);
      expect(controller.profileUnavailable, isFalse);
    });

    test(
      'a refused profile renders the roster facts rather than an error',
      () async {
        final profile = _FakeProfileRepository()..answer = null;
        final controller = MemberProfileController(
          profileProvider: () => profile,
          notesProvider: () => _FakeNotesRepository(),
        );
        addTearDown(controller.dispose);

        await controller.open('222');

        expect(controller.profile, isNull);
        expect(controller.error, isNull);
        // The popover reads this and says so rather than showing a spinner.
        expect(controller.profileUnavailable, isTrue);
      },
    );

    test('a failed fetch is reported and can be retried', () async {
      final profile = _FakeProfileRepository()..failNext = true;
      final controller = MemberProfileController(
        profileProvider: () => profile,
        notesProvider: () => _FakeNotesRepository(),
      );
      addTearDown(controller.dispose);

      await controller.open('222');
      expect(controller.error, isNotNull);
      expect(controller.profile, isNull);

      await controller.retry();
      expect(controller.error, isNull);
      expect(controller.profile?.displayName, 'Mira');
    });

    test(
      'reopening the same member keeps the profile it already holds',
      () async {
        final profile = _FakeProfileRepository();
        final controller = MemberProfileController(
          profileProvider: () => profile,
          notesProvider: () => _FakeNotesRepository(),
        );
        addTearDown(controller.dispose);

        await controller.open('222');
        await controller.open('222');
        expect(profile.requestedIds, ['222']);
      },
    );

    test('opening another member refetches', () async {
      final profile = _FakeProfileRepository();
      final controller = MemberProfileController(
        profileProvider: () => profile,
        notesProvider: () => _FakeNotesRepository(),
      );
      addTearDown(controller.dispose);

      await controller.open('222');
      await controller.open('333');

      expect(profile.requestedIds, ['222', '333']);
      expect(controller.profile?.userId, '333');
    });

    test(
      'a transport with no profile plane marks the profile unavailable',
      () async {
        final controller = MemberProfileController(
          profileProvider: () => null,
          notesProvider: () => _FakeNotesRepository(),
        );
        addTearDown(controller.dispose);

        await controller.open('222');

        expect(controller.profileUnavailable, isTrue);
        expect(controller.isLoading, isFalse);
      },
    );
  });

  group('notes', () {
    test('a note can be added, edited, and removed', () async {
      final notes = _FakeNotesRepository();
      final controller = MemberProfileController(
        profileProvider: () => _FakeProfileRepository(),
        notesProvider: () => notes,
      );
      addTearDown(controller.dispose);
      await controller.open('222');

      expect(await controller.saveNote('met at the offsite'), isTrue);
      expect(notes.written.single, ('222', 'met at the offsite'));
      expect(controller.note, 'met at the offsite');

      expect(await controller.saveNote('sends the Thursday digest'), isTrue);
      expect(notes.written.last, ('222', 'sends the Thursday digest'));

      expect(await controller.saveNote('  '), isTrue);
      expect(notes.written.last, ('222', null));
      expect(controller.note, isNull);
    });

    test('a note survives a restart', () async {
      // The account's notes live on Discord's servers, so a restart is a new
      // store reading the same account: what the transport still holds is
      // what the next session shows.
      final notes = _FakeNotesRepository()
        ..held = {'222': 'met at the offsite'};
      final first = MemberProfileController(
        profileProvider: () => _FakeProfileRepository(),
        notesProvider: () => notes,
      );
      await first.open('222');
      await first.saveNote('sends the Thursday digest');
      first.dispose();

      final restarted = MemberProfileController(
        profileProvider: () => _FakeProfileRepository(),
        notesProvider: () => notes,
      );
      addTearDown(restarted.dispose);
      await restarted.open('222');

      expect(restarted.note, 'sends the Thursday digest');
    });

    test('a note edited on another device repaints the open popover', () async {
      final notes = _FakeNotesRepository();
      final controller = MemberProfileController(
        profileProvider: () => _FakeProfileRepository(),
        notesProvider: () => notes,
      );
      addTearDown(controller.dispose);
      await controller.open('222');

      var repainted = false;
      controller.addListener(() => repainted = true);
      notes.push({'222': 'moved servers'});
      // The notes store is a broadcast stream: the revision lands on the
      // next turn of the event loop.
      await pumpEventQueue();
      expect(controller.note, 'moved servers');
      expect(repainted, isTrue);
    });

    test('a refused note is reported, not thrown', () async {
      final notes = _FakeNotesRepository()..refuse = true;
      final controller = MemberProfileController(
        profileProvider: () => _FakeProfileRepository(),
        notesProvider: () => notes,
      );
      addTearDown(controller.dispose);
      await controller.open('222');

      expect(
        await controller.saveNote('too many notes on this account'),
        isFalse,
      );
      expect(controller.noteRefused, isTrue);
      expect(controller.note, isNull);
    });
  });
}

final class _FakeProfileRepository implements UserProfileRepository {
  final List<String> requestedIds = [];
  bool failNext = false;
  OtherUserProfile? answer = const OtherUserProfile(
    userId: '222',
    username: 'mira',
    displayName: 'Mira',
    discriminator: '0',
    bio: 'ships the parser',
  );

  @override
  UserProfile? get current => null;

  @override
  Stream<UserProfile> get updates => const Stream.empty();

  @override
  Future<UserProfile?> load() async => null;

  @override
  Future<UserProfile?> apply(UserProfilePatch patch) async => null;

  @override
  Future<OtherUserProfile?> loadProfileOf(String userId) async {
    requestedIds.add(userId);
    if (failNext) {
      failNext = false;
      throw StateError('offline');
    }
    final stored = answer;
    if (stored == null) return null;
    return OtherUserProfile(
      userId: userId,
      username: stored.username,
      displayName: stored.displayName,
      discriminator: stored.discriminator,
      bio: stored.bio,
    );
  }
}

final class _FakeNotesRepository implements UserNotesRepository {
  Map<String, String> held = {};
  final List<(String, String?)> written = [];
  bool refuse = false;
  final StreamController<UserNotes> _updates = StreamController.broadcast();

  @override
  UserNotes get current => UserNotes(byUserId: held);

  @override
  bool get isLoaded => true;

  @override
  Stream<UserNotes> get updates => _updates.stream;

  @override
  Future<UserNotes> load() async => current;

  @override
  Future<bool> setNote({required String userId, required String? note}) async {
    written.add((userId, note));
    if (refuse) return false;
    if (note == null || note.isEmpty) {
      held.remove(userId);
    } else {
      held[userId] = note;
    }
    _updates.add(current);
    return true;
  }

  void push(Map<String, String> next) {
    held = next;
    _updates.add(current);
  }
}
