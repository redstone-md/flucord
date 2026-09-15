import 'package:flucord/src/application/multi_factor_auth_controller.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/domain/multi_factor_auth.dart';
import 'package:flucord/src/presentation/widgets/user_settings_dialog.dart';
import 'package:flucord/src/presentation/widgets/user_settings_mfa_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<MultiFactorAuthController> _pump(
  WidgetTester tester, {
  MultiFactorAuthRepository? repository,
  SecurityKeyCeremony? ceremony,
  SecurityKeyAccount? Function()? account,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = MultiFactorAuthController(
    () => repository,
    securityKeyCeremony: ceremony ?? _FakeCeremony(),
    securityKeyAccount:
        account ??
        () => const SecurityKeyAccount(userId: 'user-1', displayName: 'Ada'),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: MfaSettingsSection(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('the secret appears only once enrolment begins', (tester) async {
    final controller = await _pump(tester, repository: _FakeMfa());

    expect(find.byKey(const ValueKey('mfa-secret')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mfa-begin')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mfa-secret')), findsOneWidget);
    expect(find.text(controller.secret!.readable), findsOneWidget);
    expect(
      find.text(
        'Shown once. If you lose it before the first code works, '
        'start again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the code is sent and the backup codes come back', (
    tester,
  ) async {
    final repository = _FakeMfa();
    await _pump(tester, repository: repository);
    await tester.tap(find.byKey(const ValueKey('mfa-begin')));
    await tester.pumpAndSettle();

    // Nothing to send until six digits are in.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('mfa-confirm')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mfa-enrol-code')),
      '123456',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-confirm')));
    await tester.pumpAndSettle();

    expect(repository.enabled.single.$2, '123456');
    expect(find.byKey(const ValueKey('mfa-enrolled')), findsOneWidget);
    expect(find.byKey(const ValueKey('mfa-backup-aaaa-bbbb')), findsOneWidget);
    // The secret is gone from the screen the moment it is no longer needed.
    expect(find.byKey(const ValueKey('mfa-secret')), findsNothing);
  });

  testWidgets('a refused code is explained and the secret stays', (
    tester,
  ) async {
    final controller = await _pump(
      tester,
      repository: _FakeMfa()..acceptCode = false,
    );
    await tester.tap(find.byKey(const ValueKey('mfa-begin')));
    await tester.pumpAndSettle();
    final secret = controller.secret;

    await tester.enterText(
      find.byKey(const ValueKey('mfa-enrol-code')),
      '000000',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('That code was not accepted. Try the next one.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mfa-error')), findsNothing);
    expect(controller.secret, secret);
  });

  testWidgets('cancelling drops the secret', (tester) async {
    final controller = await _pump(tester, repository: _FakeMfa());
    await tester.tap(find.byKey(const ValueKey('mfa-begin')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mfa-cancel')));
    await tester.pumpAndSettle();

    expect(controller.secret, isNull);
    expect(find.byKey(const ValueKey('mfa-begin')), findsOneWidget);
  });

  testWidgets('an enrolment Discord sent no codes for says so', (tester) async {
    await _pump(tester, repository: _FakeMfa()..withCodes = false);
    await tester.tap(find.byKey(const ValueKey('mfa-begin')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mfa-enrol-code')),
      '123456',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mfa-no-backup')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mfa-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mfa-begin')), findsOneWidget);
  });

  testWidgets('two-factor is switched off with a current code', (tester) async {
    final repository = _FakeMfa();
    await _pump(tester, repository: repository);

    await tester.enterText(
      find.byKey(const ValueKey('mfa-disable-code')),
      '654321',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-disable')));
    await tester.pumpAndSettle();

    expect(repository.disabled, ['654321']);
  });

  testWidgets('a failure says nothing was changed', (tester) async {
    await _pump(tester, repository: _FakeMfa()..failNext = true);

    await tester.enterText(
      find.byKey(const ValueKey('mfa-disable-code')),
      '654321',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-disable')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mfa-error')), findsOneWidget);
  });

  testWidgets('text-message codes are switched on from the page', (
    tester,
  ) async {
    final repository = _FakeMfa();
    await _pump(tester, repository: repository);

    await tester.tap(find.byKey(const ValueKey('mfa-sms-enable')));
    await tester.pumpAndSettle();

    expect(repository.smsEnabled, isTrue);
  });

  testWidgets('stopping text codes needs the password, and forgets it', (
    tester,
  ) async {
    final repository = _FakeMfa();
    await _pump(tester, repository: repository);

    // Nothing to send until the password is there.
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('mfa-sms-disable')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mfa-password')),
      'hunter2',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-sms-disable')));
    await tester.pumpAndSettle();

    expect(repository.passwords, ['hunter2']);
    // The field is emptied rather than left holding the password.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('mfa-password')))
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('backup codes are shown again, and minted again', (tester) async {
    final repository = _FakeMfa();
    await _pump(tester, repository: repository);

    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('mfa-view-codes')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mfa-password')),
      'hunter2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mfa-disable-code')),
      '123456',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-view-codes')));
    await tester.pumpAndSettle();

    expect(repository.viewed.single, ('123456', 'view-1', false));
    expect(find.byKey(const ValueKey('mfa-backup-aaaa-bbbb')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mfa-done')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mfa-password')),
      'hunter2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mfa-disable-code')),
      '123456',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-regenerate-codes')));
    await tester.pumpAndSettle();

    expect(repository.viewed.last, ('123456', 'regen-1', true));
    expect(find.byKey(const ValueKey('mfa-backup-cccc-dddd')), findsOneWidget);
  });

  testWidgets('a wrong password reads as a refusal, not a crash', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeMfa()..acceptCode = false);

    await tester.enterText(find.byKey(const ValueKey('mfa-password')), 'wrong');
    await tester.enterText(
      find.byKey(const ValueKey('mfa-disable-code')),
      '000000',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-view-codes')));
    await tester.pumpAndSettle();

    expect(
      find.text('That code was not accepted. Try the next one.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mfa-error')), findsNothing);
  });

  testWidgets('leaving the page forgets the secret', (tester) async {
    final controller = await _pump(tester, repository: _FakeMfa());
    await tester.tap(find.byKey(const ValueKey('mfa-begin')));
    await tester.pumpAndSettle();
    expect(controller.secret, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // A credential does not outlive the page that showed it.
    expect(controller.secret, isNull);
  });

  testWidgets('a security key is added with a name and the password', (
    tester,
  ) async {
    final repository = _FakeMfa();
    final ceremony = _FakeCeremony();
    await _pump(tester, repository: repository, ceremony: ceremony);

    // Nothing to send until the name and password are both in.
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('mfa-security-key-add')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mfa-security-key-name')),
      'Hello key',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mfa-security-key-password')),
      'hunter2',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-security-key-add')));
    await tester.pumpAndSettle();

    expect(repository.challengePasswords, ['hunter2']);
    expect(repository.registered.single.$1, 'Hello key');
    expect(
      find.byKey(const ValueKey('mfa-security-key-added')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mfa-security-key-cred-1')),
      findsOneWidget,
    );
    // Back on the form: the password did not sit in the field while the
    // prompt was up.
    await tester.tap(find.byKey(const ValueKey('mfa-security-key-done')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('mfa-security-key-password')),
          )
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('a machine with no platform authenticator says so', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeMfa(),
      ceremony: const UnavailableSecurityKeyCeremony(),
    );

    expect(
      find.byKey(const ValueKey('mfa-security-key-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mfa-security-key-add')), findsNothing);
  });

  testWidgets('a closed prompt is explained, not read as a failure', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeMfa(),
      ceremony: _FakeCeremony()..decline = true,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mfa-security-key-name')),
      'Hello key',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mfa-security-key-password')),
      'hunter2',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-security-key-add')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mfa-security-key-refusal')),
      findsOneWidget,
    );
    expect(
      find.text('The prompt was closed before a key was made.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mfa-error')), findsNothing);
  });

  testWidgets('a refused password is explained by the security key block', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeMfa()..acceptPassword = false);

    await tester.enterText(
      find.byKey(const ValueKey('mfa-security-key-name')),
      'Hello key',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mfa-security-key-password')),
      'wrong',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mfa-security-key-add')));
    await tester.pumpAndSettle();

    expect(find.text('That password was not accepted.'), findsOneWidget);
    expect(find.byKey(const ValueKey('mfa-error')), findsNothing);
  });

  testWidgets('a registered key is listed and can be removed', (tester) async {
    final repository = _FakeMfa()
      ..securityKeys = const [SecurityKey(id: 'cred-1', name: 'Hello key')];
    await _pump(tester, repository: repository);

    expect(
      find.byKey(const ValueKey('mfa-security-key-cred-1')),
      findsOneWidget,
    );
    // Nothing to remove without the password.
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('mfa-security-key-remove-cred-1')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mfa-security-key-password')),
      'hunter2',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mfa-security-key-remove-cred-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mfa-security-key-cred-1')), findsNothing);
    expect(find.byKey(const ValueKey('mfa-security-key-none')), findsOneWidget);
  });

  testWidgets('the settings window offers the page and opens it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = UserSettingsController(() => null);
    addTearDown(settings.dispose);
    final mfa = MultiFactorAuthController(_FakeMfa.new);
    addTearDown(mfa.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: UserSettingsDialog(controller: settings, mfaController: mfa),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-security')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-section-mfa')), findsOneWidget);
    expect(find.byKey(const ValueKey('mfa-begin')), findsOneWidget);
  });

  testWidgets('a session with no account to secure says why', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = UserSettingsController(() => null);
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(body: UserSettingsDialog(controller: settings)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-security')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('user-mfa-unavailable')), findsOneWidget);
  });
}

final class _FakeMfa implements MultiFactorAuthRepository {
  final List<(TotpSecret, String)> enabled = [];
  final List<String> disabled = [];
  bool acceptCode = true;
  bool withCodes = true;
  bool failNext = false;
  bool smsEnabled = false;
  final List<String> passwords = [];
  final List<(String, String, bool)> viewed = [];

  List<SecurityKey> securityKeys = const [];
  final List<String> challengePasswords = [];
  final List<(String, String, SecurityKeyRegistration)> registered = [];
  final List<(SecurityKey, String)> removed = [];
  bool acceptPassword = true;

  @override
  Future<List<SecurityKey>> loadSecurityKeys() async => securityKeys;

  @override
  Future<String?> requestSecurityKeyChallenge(String password) async {
    if (failNext) {
      failNext = false;
      throw StateError('challenge failed');
    }
    challengePasswords.add(password);
    return acceptPassword ? 'challenge-1' : null;
  }

  @override
  Future<bool> registerSecurityKey({
    required String name,
    required String challenge,
    required SecurityKeyRegistration registration,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('register failed');
    }
    registered.add((name, challenge, registration));
    securityKeys = [
      ...securityKeys,
      SecurityKey(id: registration.credentialId, name: name),
    ];
    return true;
  }

  @override
  Future<bool> removeSecurityKey(SecurityKey key, String password) async {
    if (failNext) {
      failNext = false;
      throw StateError('remove failed');
    }
    removed.add((key, password));
    securityKeys = [
      for (final other in securityKeys)
        if (other.id != key.id) other,
    ];
    return true;
  }

  @override
  Future<MfaEnrolment?> enableTotp({
    required TotpSecret secret,
    required String code,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('enable failed');
    }
    if (!acceptCode) return null;
    enabled.add((secret, code));
    return MfaEnrolment(
      token: 'reissued',
      backupCodes: withCodes ? const ['aaaa-bbbb'] : const [],
    );
  }

  @override
  Future<bool> disableTotp(String code) async {
    if (failNext) {
      failNext = false;
      throw StateError('disable failed');
    }
    if (!acceptCode) return false;
    disabled.add(code);
    return true;
  }

  @override
  Future<bool> enableSms() async {
    if (failNext) {
      failNext = false;
      throw StateError('sms failed');
    }
    if (!acceptCode) return false;
    smsEnabled = true;
    return true;
  }

  @override
  Future<bool> disableSms(String password) async {
    if (failNext) {
      failNext = false;
      throw StateError('sms failed');
    }
    if (!acceptCode) return false;
    passwords.add(password);
    smsEnabled = false;
    return true;
  }

  @override
  Future<BackupCodeNonces?> requestBackupCodeChallenge(String password) async {
    if (failNext) {
      failNext = false;
      throw StateError('challenge failed');
    }
    if (!acceptCode) return null;
    passwords.add(password);
    return const BackupCodeNonces(view: 'view-1', regenerate: 'regen-1');
  }

  @override
  Future<List<String>?> viewBackupCodes({
    required String key,
    required BackupCodeNonces nonces,
    bool regenerate = false,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('view failed');
    }
    if (!acceptCode) return null;
    viewed.add((key, nonces.forRequest(regenerating: regenerate), regenerate));
    return regenerate ? const ['cccc-dddd'] : const ['aaaa-bbbb'];
  }
}

final class _FakeCeremony implements SecurityKeyCeremony {
  bool decline = false;

  @override
  bool get isAvailable => true;

  @override
  Future<SecurityKeyRegistration?> createCredential({
    required String challenge,
    required SecurityKeyAccount account,
  }) async => decline
      ? null
      : const SecurityKeyRegistration(
          credentialId: 'cred-1',
          attestationObject: 'attestation',
          clientDataJson: 'client-data',
        );
}
