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
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = MultiFactorAuthController(() => repository);
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
