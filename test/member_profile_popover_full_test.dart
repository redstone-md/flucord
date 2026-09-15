import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/member_profile_controller.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/user_notes.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/presentation/widgets/member_profile_popover.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('the popover renders the fetched profile', (tester) async {
    final profile = _FakeProfileRepository(profile: _fullProfile);
    final notes = _FakeNotesRepository()..held = {'222': 'met at the offsite'};
    final controller = MemberProfileController(
      profileProvider: () => profile,
      notesProvider: () => notes,
    );
    addTearDown(controller.dispose);

    await controller.open('222');
    await _pumpPopover(tester, controller);

    // The identity block the roster knows, unchanged.
    expect(find.text('Mira Chen'), findsOneWidget);
    // The fetched sections.
    expect(find.byKey(const ValueKey('full-profile-sections')), findsOne);
    expect(find.text('ships the parser'), findsOne);
    expect(find.text('she/her'), findsOne);
    expect(find.byKey(const ValueKey('profile-badges')), findsOne);
    expect(find.byKey(const ValueKey('profile-connections')), findsOne);
    expect(find.byKey(const ValueKey('profile-mutual-servers')), findsOne);
    expect(find.byKey(const ValueKey('profile-mutual-friends')), findsOne);
    // The note the account already holds is prefilled.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('profile-note-field')))
          .controller
          ?.text,
      'met at the offsite',
    );
  });

  testWidgets('a note can be edited and saved from the popover', (
    tester,
  ) async {
    final notes = _FakeNotesRepository()..held = {'222': 'met at the offsite'};
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: _fullProfile),
      notesProvider: () => notes,
    );
    addTearDown(controller.dispose);
    await controller.open('222');
    await _pumpPopover(tester, controller);

    await tester.enterText(
      find.byKey(const ValueKey('profile-note-field')),
      'sends the Thursday digest',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('profile-note-save')), findsOne);

    await tester.tap(find.byKey(const ValueKey('profile-note-save')));
    await tester.pumpAndSettle();

    expect(notes.written.single, ('222', 'sends the Thursday digest'));
    expect(find.byKey(const ValueKey('profile-note-save')), findsNothing);
  });

  testWidgets('a blank save removes the note', (tester) async {
    final notes = _FakeNotesRepository()..held = {'222': 'stale context'};
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: _fullProfile),
      notesProvider: () => notes,
    );
    addTearDown(controller.dispose);
    await controller.open('222');
    await _pumpPopover(tester, controller);

    await tester.enterText(
      find.byKey(const ValueKey('profile-note-field')),
      '   ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-note-save')));
    await tester.pumpAndSettle();

    expect(notes.written.single, ('222', null));
    expect(notes.held, isEmpty);
  });

  testWidgets('a refused save says so and keeps the text', (tester) async {
    final notes = _FakeNotesRepository()
      ..held = {}
      ..refuse = true;
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: _fullProfile),
      notesProvider: () => notes,
    );
    addTearDown(controller.dispose);
    await controller.open('222');
    await _pumpPopover(tester, controller);

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

  testWidgets('a bare profile shows the identity block and the note only', (
    tester,
  ) async {
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(
        profile: const OtherUserProfile(userId: '222222222222222222'),
      ),
      notesProvider: () => _FakeNotesRepository(),
    );
    addTearDown(controller.dispose);
    await controller.open('222');
    await _pumpPopover(tester, controller);

    expect(find.text('Mira Chen'), findsOneWidget);
    // No bio, no badges, no mutuals: nothing but the note section, which the
    // account always owns.
    expect(find.byKey(const ValueKey('profile-badges')), findsNothing);
    expect(find.byKey(const ValueKey('profile-connections')), findsNothing);
    expect(find.byKey(const ValueKey('profile-mutual-servers')), findsNothing);
    expect(find.byKey(const ValueKey('profile-mutual-friends')), findsNothing);
    expect(find.byKey(const ValueKey('profile-note-section')), findsOne);
  });

  testWidgets('a refused fetch keeps the popover useful', (tester) async {
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(profile: null),
      notesProvider: () => _FakeNotesRepository(),
    );
    addTearDown(controller.dispose);
    await controller.open('222');
    await _pumpPopover(tester, controller);

    // The roster facts still render; the fetched sections are simply absent.
    expect(find.text('Mira Chen'), findsOneWidget);
    expect(find.byKey(const ValueKey('full-profile-sections')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no profile controller draws the identity block alone', (
    tester,
  ) async {
    await _pumpPopover(tester, null);

    expect(find.text('Mira Chen'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-note-section')), findsNothing);
  });

  testWidgets('the note field is disabled with no account behind it', (
    tester,
  ) async {
    final controller = MemberProfileController(
      profileProvider: () => null,
      notesProvider: () => null,
    );
    addTearDown(controller.dispose);
    await controller.open('222');
    await _pumpPopover(tester, controller);

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('profile-note-field')))
          .enabled,
      isFalse,
    );
  });

  testWidgets('a profile carrying many badges wraps them, not overflows', (
    tester,
  ) async {
    final controller = MemberProfileController(
      profileProvider: () => _FakeProfileRepository(
        profile: OtherUserProfile(
          userId: '222222222222222222',
          username: 'mira',
          displayName: 'Mira Chen',
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
    await controller.open('222');
    await _pumpPopover(tester, controller);

    expect(find.byKey(const ValueKey('profile-badges')), findsOne);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPopover(
  WidgetTester tester,
  MemberProfileController? controller,
) async {
  // Tall enough that the whole popover, note section included, is on
  // screen: a control scrolled out of the viewport cannot be tapped.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: Center(
          child: MemberProfilePopover(
            member: _member,
            spaceId: 'guild-1',
            canMessage: true,
            onMessage: () {},
            profile: controller,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

const _member = Member(
  id: '222222222222222222',
  displayName: 'Mira Chen',
  initials: 'MC',
  role: 'Product design',
  presence: Presence.online,
  colorValue: 0xff665f82,
  spaceIds: {'guild-1'},
  rolesBySpace: {'guild-1': 'Product design'},
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
}
