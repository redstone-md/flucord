import 'dart:async';

import 'package:flucord/src/application/user_profile_controller.dart';
import 'package:flucord/src/domain/user_profile.dart';
import 'package:flucord/src/presentation/widgets/account_credentials_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what the patch sends', () {
    test('a name change carries the name and the password', () {
      const patch = UserProfilePatch(username: 'mira', password: 'hunter2');

      expect(patch.needsPassword, isTrue);
      expect(patch.isEmpty, isFalse);
      expect(patch.toJson(), {'username': 'mira', 'password': 'hunter2'});
    });

    test('a password change carries both passwords', () {
      const patch = UserProfilePatch(
        newPassword: 'new-one',
        password: 'hunter2',
      );

      expect(patch.toJson(), {
        'new_password': 'new-one',
        'password': 'hunter2',
      });
    });

    test('an ordinary edit carries no password, even if one was given', () {
      // A bio edit has no use for it, and sending it anyway would put a
      // credential on a request that did not need one.
      const patch = UserProfilePatch(bio: 'hello', password: 'hunter2');

      expect(patch.needsPassword, isFalse);
      expect(patch.toJson(), {'bio': 'hello'});
    });

    test('a patch that changes no credential and nothing else is empty', () {
      expect(const UserProfilePatch(password: 'hunter2').isEmpty, isTrue);
    });
  });

  group('the controller', () {
    test('a name change reaches the repository', () async {
      final repository = _FakeProfile();
      final controller = UserProfileController(() => repository);
      addTearDown(controller.dispose);

      expect(
        await controller.changeUsername(
          username: '  mira  ',
          password: 'hunter2',
        ),
        isTrue,
      );

      // Trimmed: the spaces are part of typing, not of the name.
      expect(repository.applied.single.username, 'mira');
      expect(repository.applied.single.password, 'hunter2');
      expect(controller.wasCredentialChangeRefused, isFalse);
    });

    test('a password change reaches the repository', () async {
      final repository = _FakeProfile();
      final controller = UserProfileController(() => repository);
      addTearDown(controller.dispose);

      expect(
        await controller.changePassword(
          currentPassword: 'hunter2',
          newPassword: 'new-one',
        ),
        isTrue,
      );

      expect(repository.applied.single.newPassword, 'new-one');
    });

    test('nothing is sent without the password Discord asks for', () async {
      final repository = _FakeProfile();
      final controller = UserProfileController(() => repository);
      addTearDown(controller.dispose);

      expect(
        await controller.changeUsername(username: 'mira', password: ''),
        isFalse,
      );
      expect(
        await controller.changePassword(
          currentPassword: '',
          newPassword: 'new-one',
        ),
        isFalse,
      );

      expect(repository.applied, isEmpty);
    });

    test('a refusal is an answer, not a failure', () async {
      final repository = _FakeProfile()..accept = false;
      final controller = UserProfileController(() => repository);
      addTearDown(controller.dispose);

      expect(
        await controller.changeUsername(username: 'taken', password: 'hunter2'),
        isFalse,
      );

      expect(controller.wasCredentialChangeRefused, isTrue);
      expect(controller.error, isNull);
    });

    test('a failure is reported', () async {
      final repository = _FakeProfile()..failNext = true;
      final controller = UserProfileController(() => repository);
      addTearDown(controller.dispose);

      expect(
        await controller.changeUsername(username: 'mira', password: 'hunter2'),
        isFalse,
      );

      expect(controller.error, isA<StateError>());
      expect(controller.isSaving, isFalse);
    });

    test('a transport with no profile does nothing', () async {
      final controller = UserProfileController(() => null);
      addTearDown(controller.dispose);

      expect(
        await controller.changeUsername(username: 'mira', password: 'hunter2'),
        isFalse,
      );
    });
  });

  group('the form', () {
    testWidgets('a name change needs both a name and the password', (
      tester,
    ) async {
      final repository = _FakeProfile();
      await _pump(tester, repository);

      expect(_enabled(tester, 'credentials-save-username'), isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('credentials-username')),
        'mira',
      );
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'credentials-save-username'), isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('credentials-current-password')),
        'hunter2',
      );
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'credentials-save-username'), isTrue);

      await tester.tap(find.byKey(const ValueKey('credentials-save-username')));
      await tester.pumpAndSettle();

      expect(repository.applied.single.username, 'mira');
      // The password is cleared, and so is the name once it was taken.
      expect(_textOf(tester, 'credentials-current-password'), isEmpty);
      expect(_textOf(tester, 'credentials-username'), isEmpty);
    });

    testWidgets('a password change needs both passwords', (tester) async {
      final repository = _FakeProfile();
      await _pump(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('credentials-new-password')),
        'new-one',
      );
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'credentials-save-password'), isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('credentials-current-password')),
        'hunter2',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('credentials-save-password')));
      await tester.pumpAndSettle();

      expect(repository.applied.single.newPassword, 'new-one');
      expect(_textOf(tester, 'credentials-new-password'), isEmpty);
      expect(_textOf(tester, 'credentials-current-password'), isEmpty);
    });

    testWidgets('a refusal does not claim to know which it was', (
      tester,
    ) async {
      await _pump(tester, _FakeProfile()..accept = false);

      await tester.enterText(
        find.byKey(const ValueKey('credentials-username')),
        'taken',
      );
      await tester.enterText(
        find.byKey(const ValueKey('credentials-current-password')),
        'wrong',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('credentials-save-username')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('credentials-refused')), findsOneWidget);
    });
  });
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<FilledButton>(find.byKey(ValueKey(key))).onPressed != null;

String _textOf(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller?.text ?? '';

Future<void> _pump(WidgetTester tester, _FakeProfile repository) async {
  await tester.binding.setSurfaceSize(const Size(700, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = UserProfileController(() => repository);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AccountCredentialsSection(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeProfile implements UserProfileRepository {
  final List<UserProfilePatch> applied = [];
  final StreamController<UserProfile> _updates = StreamController.broadcast();
  bool accept = true;
  bool failNext = false;

  @override
  UserProfile? get current => null;

  @override
  Stream<UserProfile> get updates => _updates.stream;

  @override
  Future<UserProfile?> load() async => null;

  @override
  Future<UserProfile?> apply(UserProfilePatch patch) async {
    if (failNext) {
      failNext = false;
      throw StateError('patch failed');
    }
    if (!accept) return null;
    applied.add(patch);
    return const UserProfile(userId: 'user-1', username: 'mira');
  }
}
