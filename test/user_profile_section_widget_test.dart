import 'dart:async';

import 'package:flucord/src/application/user_profile_controller.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/presentation/profile_image_picker.dart';
import 'package:flucord/src/presentation/widgets/user_profile_controls.dart';
import 'package:flucord/src/presentation/widgets/user_profile_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    UserProfileController controller, {
    ProfileImagePicker picker = const _CancelledPicker(),
  }) async {
    // Tall enough that the whole form, save bar included, is on screen: a
    // control scrolled out of the viewport cannot be tapped.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => UserProfileSection(
                controller: controller,
                imagePicker: picker,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a transport with no profile plane explains itself', (
    tester,
  ) async {
    final controller = UserProfileController(() => null);
    addTearDown(controller.dispose);

    await pump(tester, controller);

    expect(find.byKey(const ValueKey('user-profile-unavailable')), findsOne);
  });

  testWidgets('the form shows the account and stages an edit', (tester) async {
    final repository = _FakeRepository();
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-section-profile')), findsOne);
    expect(find.text('rxflex'), findsWidgets);
    // Nothing to save until something changes.
    expect(find.byKey(const ValueKey('profile-save-bar')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('profile-display-name')),
      'Rx Two',
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('profile-save-bar')), findsOne);

    await tester.tap(find.byKey(const ValueKey('profile-save')));
    await tester.pumpAndSettle();

    expect(repository.patches.single.toJson(), {'global_name': 'Rx Two'});
    expect(find.byKey(const ValueKey('profile-save-bar')), findsNothing);
  });

  testWidgets('resetting drops the draft and the bar with it', (tester) async {
    final repository = _FakeRepository();
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('profile-bio')),
      'temporary',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('profile-save-bar')), findsOne);

    await tester.tap(find.byKey(const ValueKey('profile-discard')));
    await tester.pump();

    expect(find.byKey(const ValueKey('profile-save-bar')), findsNothing);
    expect(repository.patches, isEmpty);
  });

  testWidgets('an accent swatch is staged and cleared', (tester) async {
    final repository = _FakeRepository();
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.pumpAndSettle();

    final swatch = profileAccentSwatches.first;
    await tester.tap(
      find.byKey(ValueKey('profile-accent-${swatch.toRadixString(16)}')),
    );
    await tester.pump();
    expect(controller.accentColor, swatch);

    await tester.tap(find.byKey(const ValueKey('profile-accent-none')));
    await tester.pump();
    expect(controller.accentColor, isNull);

    await tester.tap(find.byKey(const ValueKey('profile-save')));
    await tester.pumpAndSettle();
    expect(repository.patches.single.toJson(), {'accent_color': null});
  });

  testWidgets('a chosen avatar is staged as a data URI', (tester) async {
    final repository = _FakeRepository();
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller, picker: const _StubPicker());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-pick-avatar')));
    await tester.pumpAndSettle();

    expect(controller.pendingAvatar.dataUri, 'data:image/png;base64,AAAA');

    await tester.tap(find.byKey(const ValueKey('profile-save')));
    await tester.pumpAndSettle();
    expect(repository.patches.single.toJson(), {
      'avatar': 'data:image/png;base64,AAAA',
    });
  });

  testWidgets('removing the stored avatar sends an explicit null', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-remove-avatar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-save')));
    await tester.pumpAndSettle();
    expect(repository.patches.single.toJson(), {'avatar': null});
  });

  testWidgets('a chosen banner is staged and a stored one can be removed', (
    tester,
  ) async {
    final repository = _FakeRepository(
      profile: const UserProfile(
        userId: '1',
        username: 'rxflex',
        bannerHash: 'ban',
      ),
    );
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller, picker: const _StubPicker());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-pick-banner')));
    await tester.pumpAndSettle();
    expect(controller.pendingBanner.dataUri, 'data:image/png;base64,AAAA');

    await tester.tap(find.byKey(const ValueKey('profile-remove-banner')));
    await tester.pumpAndSettle();
    expect(controller.pendingBanner.isUntouched, isFalse);
    expect(controller.pendingBanner.dataUri, isNull);

    await tester.tap(find.byKey(const ValueKey('profile-save')));
    await tester.pumpAndSettle();
    expect(repository.patches.single.toJson(), {'banner': null});
  });

  testWidgets('a rejected image is reported instead of staged', (tester) async {
    final repository = _FakeRepository();
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller, picker: const _RejectingPicker());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-pick-banner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('user-profile-picker-error')), findsOne);
    expect(controller.pendingBanner.isUntouched, isTrue);
  });

  testWidgets('an unreadable file falls back to a generic message', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller, picker: const _ThrowingPicker());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-pick-avatar')));
    await tester.pumpAndSettle();

    expect(find.text('That image could not be read.'), findsOne);
  });

  testWidgets('cancelling the picker stages nothing', (tester) async {
    final repository = _FakeRepository();
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-pick-avatar')));
    await tester.pumpAndSettle();

    expect(controller.pendingAvatar.isUntouched, isTrue);
    expect(
      find.byKey(const ValueKey('user-profile-picker-error')),
      findsNothing,
    );
  });

  testWidgets('a failed load offers a retry', (tester) async {
    final repository = _FakeRepository()..failLoad = true;
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('user-profile-error')), findsOne);

    repository.failLoad = false;
    await tester.tap(find.byKey(const ValueKey('user-profile-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-section-profile')), findsOne);
  });

  testWidgets('a load in flight shows progress rather than an error', (
    tester,
  ) async {
    final repository = _FakeRepository()..gate = Completer<void>();
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.pump();

    expect(find.byKey(const ValueKey('user-profile-loading')), findsOne);

    repository.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-section-profile')), findsOne);
  });

  testWidgets('a rejected save is reported and keeps the draft', (
    tester,
  ) async {
    final repository = _FakeRepository()..failWrites = true;
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('profile-bio')),
      'rejected',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('user-profile-save-error')), findsOne);
    expect(find.byKey(const ValueKey('profile-save-bar')), findsOne);
  });

  testWidgets('a legacy tag is shown next to the username', (tester) async {
    final repository = _FakeRepository(
      profile: const UserProfile(
        userId: '1',
        username: 'legacy',
        discriminator: '1234',
        pronouns: 'they/them',
        bio: 'about',
      ),
    );
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.pumpAndSettle();

    expect(find.text('legacy#1234'), findsOne);
    expect(find.text('#1234'), findsOne);
    expect(find.text('they/them'), findsWidgets);
    expect(find.text('about'), findsWidgets);
    // Nothing stored to remove, so only the replace control is offered.
    expect(find.byKey(const ValueKey('profile-remove-banner')), findsNothing);
  });

  testWidgets('a profile arriving from another device repaints the form', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final controller = UserProfileController(() => repository);
    addTearDown(controller.dispose);

    await pump(tester, controller);
    await tester.pumpAndSettle();

    repository.push(
      const UserProfile(userId: '1', username: 'rxflex', displayName: 'Remote'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Remote'), findsWidgets);
  });
}

final class _FakeRepository implements UserProfileRepository {
  _FakeRepository({UserProfile? profile})
    : _current =
          profile ??
          const UserProfile(
            userId: '1',
            username: 'rxflex',
            displayName: 'Rx',
            discriminator: '0',
            avatarHash: 'abc',
          );

  final StreamController<UserProfile> _updates = StreamController.broadcast();
  final List<UserProfilePatch> patches = [];

  UserProfile? _current;
  bool _loaded = false;
  bool failLoad = false;
  bool failWrites = false;
  Completer<void>? gate;

  // Null until the first load lands, the same as the real repository.
  @override
  UserProfile? get current => _loaded ? _current : null;

  @override
  Stream<UserProfile> get updates => _updates.stream;

  @override
  Future<UserProfile?> load() async {
    await gate?.future;
    if (failLoad) throw StateError('unreachable');
    _loaded = true;
    _updates.add(_current!);
    return _current;
  }

  @override
  Future<UserProfile?> apply(UserProfilePatch patch) async {
    if (failWrites) throw StateError('rejected');
    patches.add(patch);
    return _current;
  }

  void push(UserProfile profile) {
    _loaded = true;
    _current = profile;
    _updates.add(profile);
  }
}

final class _CancelledPicker implements ProfileImagePicker {
  const _CancelledPicker();

  @override
  Future<ProfileImageSelection?> pick() async => null;
}

final class _StubPicker implements ProfileImagePicker {
  const _StubPicker();

  @override
  Future<ProfileImageSelection?> pick() async => const ProfileImageSelection(
    name: 'avatar.png',
    dataUri: 'data:image/png;base64,AAAA',
    byteCount: 3,
  );
}

final class _RejectingPicker implements ProfileImagePicker {
  const _RejectingPicker();

  @override
  Future<ProfileImageSelection?> pick() async =>
      throw const ProfileImageRejected(ProfileImageRejection.tooLarge);
}

final class _ThrowingPicker implements ProfileImagePicker {
  const _ThrowingPicker();

  @override
  Future<ProfileImageSelection?> pick() async => throw StateError('io');
}
