import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/member_profile_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/user_notes.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/presentation/widgets/member_profile_card.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('the card lays the fetched profile over the member', (
    tester,
  ) async {
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: _fullProfile),
      notesProvider: () => _FakeNotesRepository(),
    );
    addTearDown(controller.dispose);

    await _pumpCard(tester, controller);

    expect(find.text('Mira Chen'), findsOneWidget);
    expect(find.text('mira · she/her'), findsOneWidget);
    expect(find.text('ships the parser'), findsOne);
    expect(find.byKey(const ValueKey('profile-card-badges')), findsOne);
    expect(find.text('1 mutual friend · 1 mutual server'), findsOne);
    expect(find.byKey(const ValueKey('profile-card-banner-image')), findsOne);
    expect(find.byKey(const ValueKey('profile-card-decoration')), findsOne);
  });

  testWidgets('opening the card fetches the profile', (tester) async {
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: _fullProfile),
      notesProvider: () => _FakeNotesRepository(),
    );
    addTearDown(controller.dispose);

    await _pumpCard(tester, controller);

    expect(controller.openUserId, _member.id);
  });

  testWidgets('a note can be edited and saved from the card', (tester) async {
    final notes = _FakeNotesRepository()..held = {_member.id: 'offsite'};
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: _fullProfile),
      notesProvider: () => notes,
    );
    addTearDown(controller.dispose);
    await _pumpCard(tester, controller);
    await _openNote(tester);

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('profile-note-field')))
          .controller
          ?.text,
      'offsite',
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-note-field')),
      'sends the Thursday digest',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-note-save')));
    await tester.pumpAndSettle();

    expect(notes.written.single, (_member.id, 'sends the Thursday digest'));
    expect(find.byKey(const ValueKey('profile-note-save')), findsNothing);
  });

  testWidgets('a note that changes elsewhere replaces the untouched field', (
    tester,
  ) async {
    final notes = _FakeNotesRepository()..held = {_member.id: 'offsite'};
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: _fullProfile),
      notesProvider: () => notes,
    );
    addTearDown(controller.dispose);
    await _pumpCard(tester, controller);
    await _openNote(tester);

    notes.updateElsewhere(_member.id, 'moved to the infra team');
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('profile-note-field')))
          .controller
          ?.text,
      'moved to the infra team',
    );
  });

  testWidgets('a note that changes elsewhere leaves an edit in progress', (
    tester,
  ) async {
    final notes = _FakeNotesRepository()..held = {_member.id: 'offsite'};
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: _fullProfile),
      notesProvider: () => notes,
    );
    addTearDown(controller.dispose);
    await _pumpCard(tester, controller);
    await _openNote(tester);

    await tester.enterText(
      find.byKey(const ValueKey('profile-note-field')),
      'my own words',
    );
    await tester.pump();
    notes.updateElsewhere(_member.id, 'moved to the infra team');
    await tester.pump();

    expect(find.text('my own words'), findsOne);
  });

  testWidgets('a blank save removes the note', (tester) async {
    final notes = _FakeNotesRepository()..held = {_member.id: 'stale'};
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: _fullProfile),
      notesProvider: () => notes,
    );
    addTearDown(controller.dispose);
    await _pumpCard(tester, controller);
    await _openNote(tester);

    await tester.enterText(
      find.byKey(const ValueKey('profile-note-field')),
      '   ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-note-save')));
    await tester.pumpAndSettle();

    expect(notes.written.single, (_member.id, null));
    expect(notes.held, isEmpty);
  });

  testWidgets('a refused save says so and keeps the text', (tester) async {
    final notes = _FakeNotesRepository()..refuse = true;
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: _fullProfile),
      notesProvider: () => notes,
    );
    addTearDown(controller.dispose);
    await _pumpCard(tester, controller);
    await _openNote(tester);

    await tester.enterText(
      find.byKey(const ValueKey('profile-note-field')),
      'the account holds too many notes',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-note-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-note-refused')), findsOne);
    expect(find.text('the account holds too many notes'), findsOne);
  });

  testWidgets('a bare profile hides what it did not fill', (tester) async {
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(
        profile: const OtherUserProfile(userId: '222222222222222222'),
      ),
      notesProvider: () => _FakeNotesRepository(),
    );
    addTearDown(controller.dispose);
    await _pumpCard(tester, controller);

    expect(find.text('Mira Chen'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-card-badges')), findsNothing);
    expect(find.byKey(const ValueKey('profile-card-mutual')), findsNothing);
    expect(find.byKey(const ValueKey('profile-card-bio')), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-card-banner-image')),
      findsNothing,
    );
  });

  testWidgets('a refused fetch keeps the card useful', (tester) async {
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: null),
      notesProvider: () => _FakeNotesRepository(),
    );
    addTearDown(controller.dispose);
    await _pumpCard(tester, controller);

    expect(find.text('Mira Chen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no account behind it there is no note', (tester) async {
    final controller = MemberProfileController(
      profileProvider: () => null,
      notesProvider: () => null,
    );
    addTearDown(controller.dispose);
    await _pumpCard(tester, controller);

    await tester.tap(find.byKey(const ValueKey('profile-card-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('copy-member-id')), findsOne);
    expect(find.byKey(const ValueKey('profile-card-note')), findsNothing);
  });

  testWidgets('many badges show three and a count, without overflow', (
    tester,
  ) async {
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(
        profile: OtherUserProfile(
          userId: '222222222222222222',
          badges: [
            for (var index = 0; index < 20; index++)
              ProfileBadge(
                id: 'badge-$index',
                description: 'Badge number $index',
                icon: 'hash$index',
              ),
          ],
        ),
      ),
      notesProvider: () => _FakeNotesRepository(),
    );
    addTearDown(controller.dispose);
    await _pumpCard(tester, controller);

    expect(find.text('+17'), findsOne);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openNote(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('profile-card-more')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('profile-card-note')));
  await tester.pumpAndSettle();
}

Future<void> _pumpCard(
  WidgetTester tester,
  MemberProfileController controller,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Center(
          child: MemberProfileCard(
            member: _member,
            spaceId: 'guild-1',
            workspace: _workspace,
            profile: controller,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Holds the one mutual server, which the card names from here.
final _workspace = ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: '666666666666666666',
      name: 'Flucord HQ',
      monogram: 'FH',
      colorValue: 0xff2e4a7a,
    ),
  ],
  channels: const [],
  members: const [_member],
  messages: const [],
  currentMemberId: '111111111111111111',
);

const _member = Member(
  id: '222222222222222222',
  displayName: 'Mira Chen',
  initials: 'MC',
  role: 'Product design',
  presence: Presence.online,
  colorValue: 0xff665f82,
  spaceIds: {'guild-1'},
);

const _fullProfile = OtherUserProfile(
  userId: '222222222222222222',
  username: 'mira',
  displayName: 'Mira Chen',
  discriminator: '0',
  bio: 'ships the parser',
  pronouns: 'she/her',
  avatarHash: 'mhash',
  bannerHash: 'a_bhash',
  accentColor: 0x5865f2,
  decoration: ProfileDecoration(asset: 'a_deco'),
  badges: [
    ProfileBadge(
      id: 'legacy_username',
      description: 'Originally known as mira#1234',
      icon: '6de27dcd513adaa7c2eb5a206fb0d47c',
    ),
  ],
  connections: [
    ProfileConnection(type: 'twitter', name: 'discord', verified: true),
  ],
  mutualServers: [MutualServer(id: '666666666666666666', nickname: 'Flucord')],
  mutualFriends: [
    MutualFriend(id: '333', displayName: 'Roman Vale', username: 'roman'),
  ],
);

final class _FakeProfileRepository implements UserProfileRepository {
  _FakeProfileRepository({this.profile});

  final OtherUserProfile? profile;

  @override
  UserProfile? get current => null;

  @override
  Stream<UserProfile> get updates => const Stream.empty();

  @override
  Future<UserProfile?> load() async => null;

  @override
  Future<UserProfile?> apply(UserProfilePatch patch) async => null;

  @override
  Future<OtherUserProfile?> loadProfileOf(String userId) async => profile;
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
    if (refuse) return false;
    written.add((userId, note));
    if (note == null || note.isEmpty) {
      held.remove(userId);
    } else {
      held[userId] = note;
    }
    _updates.add(current);
    return true;
  }

  /// A note written on another device, which reaches this one as an update.
  void updateElsewhere(String userId, String note) {
    held[userId] = note;
    _updates.add(current);
  }
}
