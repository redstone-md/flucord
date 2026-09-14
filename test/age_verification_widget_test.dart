import 'package:flucord/src/application/age_verification_controller.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/domain/age_verification.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/presentation/widgets/user_settings_age_section.dart';
import 'package:flucord/src/presentation/widgets/user_settings_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _wallet = AgeVerificationMethod(
  method: 'google_wallet',
  vendor: 'google',
  title: 'Google Wallet',
  description: 'Show a saved ID',
  providedBy: 'Google',
);

const _face = AgeVerificationMethod(
  method: 'facial_age_estimation',
  vendor: 'incode',
);

Future<AgeVerificationController> _pump(
  WidgetTester tester, {
  AgeVerificationRepository? repository,
  _RecordingLauncher? launcher,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = AgeVerificationController(
    () => repository,
    launcher: launcher ?? _RecordingLauncher(),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AgeVerificationSection(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('the page names every method and who runs it', (tester) async {
    await _pump(
      tester,
      repository: _FakeAgeVerification(const [_wallet, _face]),
    );

    expect(find.byKey(const ValueKey('age-disclaimer')), findsOneWidget);
    expect(find.byKey(const ValueKey('age-method-google_wallet')), findsOne);
    expect(find.text('Google Wallet'), findsOneWidget);
    expect(find.text('Show a saved ID'), findsOneWidget);
    expect(find.text('Run by Google'), findsOneWidget);
    // With no separate provider, the vendor is named instead of nobody.
    expect(find.text('Run by incode'), findsOneWidget);
    expect(find.text('facial_age_estimation'), findsOneWidget);
  });

  testWidgets('starting opens the vendor page outside the app', (tester) async {
    final launcher = _RecordingLauncher();
    await _pump(
      tester,
      repository: _FakeAgeVerification(const [_wallet]),
      launcher: launcher,
    );

    await tester.tap(find.byKey(const ValueKey('age-start-google_wallet')));
    await tester.pumpAndSettle();

    expect(launcher.opened.single.host, 'verify.example.com');
  });

  testWidgets('a method the account may not use is named as refused', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeAgeVerification(const [_wallet])..accept = false,
    );

    await tester.tap(find.byKey(const ValueKey('age-start-google_wallet')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('age-refused')), findsOneWidget);
    expect(
      find.text('Discord will not start Google Wallet for this account.'),
      findsOneWidget,
    );
  });

  testWidgets('a method needing a vendor app says so rather than nothing', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeAgeVerification(const [_wallet])..url = '',
    );

    await tester.tap(find.byKey(const ValueKey('age-start-google_wallet')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('age-vendor-surface')), findsOneWidget);
  });

  testWidgets('an account with no way to verify is told', (tester) async {
    await _pump(tester, repository: _FakeAgeVerification(const []));

    expect(find.byKey(const ValueKey('age-none')), findsOneWidget);
  });

  testWidgets('a read that failed offers a retry', (tester) async {
    await _pump(
      tester,
      repository: _FakeAgeVerification(const [_wallet])..failFirstLoad = true,
    );

    expect(find.byKey(const ValueKey('age-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('age-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('age-method-google_wallet')), findsOne);
  });

  testWidgets('a transport with none renders nothing to act on', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(const ValueKey('age-error')), findsNothing);
    expect(find.byKey(const ValueKey('age-loading')), findsNothing);
  });

  testWidgets('the settings window offers the page and opens it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = UserSettingsController(() => null);
    addTearDown(settings.dispose);
    final age = AgeVerificationController(
      () => _FakeAgeVerification(const [_wallet]),
      launcher: _RecordingLauncher(),
    );
    addTearDown(age.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: UserSettingsDialog(controller: settings, ageController: age),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-age')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-section-age')), findsOneWidget);
    expect(find.byKey(const ValueKey('age-method-google_wallet')), findsOne);
  });

  testWidgets('a session with no account to verify says why', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('settings-nav-age')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('user-age-unavailable')), findsOneWidget);
  });
}

final class _FakeAgeVerification implements AgeVerificationRepository {
  _FakeAgeVerification(this._methods);

  final List<AgeVerificationMethod> _methods;
  bool accept = true;
  bool failFirstLoad = false;
  String url = 'https://verify.example.com/session';

  @override
  Future<List<AgeVerificationMethod>> loadMethods() async {
    if (failFirstLoad) {
      failFirstLoad = false;
      throw StateError('load failed');
    }
    return _methods;
  }

  @override
  Future<AgeVerificationStart?> start(AgeVerificationMethod method) async =>
      accept ? AgeVerificationStart(continueUrl: url) : null;
}

final class _RecordingLauncher implements ExternalLinkLauncher {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}
