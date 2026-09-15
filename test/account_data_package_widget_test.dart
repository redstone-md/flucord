import 'package:flucord/src/application/account_data_package_controller.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/domain/account_data_package.dart';
import 'package:flucord/src/presentation/widgets/user_settings_data_package_section.dart';
import 'package:flucord/src/presentation/widgets/user_settings_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _createdAt = DateTime.utc(2026, 9, 1);

Future<AccountDataPackageController> _pump(
  WidgetTester tester, {
  AccountDataPackageRepository? repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = AccountDataPackageController(() => repository);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DataPackageSettingsSection(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('an account that never asked says so, and can ask', (
    tester,
  ) async {
    final repository = _FakeDataPackage();
    await _pump(tester, repository: repository);

    expect(find.byKey(const ValueKey('data-package-none')), findsOneWidget);
    expect(find.byKey(const ValueKey('data-package-request')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('data-package-explainer')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('data-package-request')));
    await tester.pumpAndSettle();

    expect(repository.requested, isTrue);
    expect(
      find.byKey(const ValueKey('data-package-status-pending')),
      findsOneWidget,
    );
  });

  testWidgets('a running request is stated and cannot be asked again', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeDataPackage()
        ..package = AccountDataPackage(
          harvestId: '1234',
          status: DataPackageStatus.processing,
          createdAt: _createdAt,
          progressPercent: 40,
          progressStep: 'collecting messages',
        ),
    );

    expect(
      find.byKey(const ValueKey('data-package-status-processing')),
      findsOneWidget,
    );
    expect(find.textContaining('40% done'), findsOneWidget);
    expect(find.byKey(const ValueKey('data-package-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('data-package-step')), findsOneWidget);
    // Discord refuses a second while the first is running, so none is
    // offered.
    expect(find.byKey(const ValueKey('data-package-request')), findsNothing);
    expect(find.byKey(const ValueKey('data-package-refresh')), findsOneWidget);
  });

  testWidgets('a completed request says where the link went', (tester) async {
    await _pump(
      tester,
      repository: _FakeDataPackage()
        ..package = AccountDataPackage(
          harvestId: '1234',
          status: DataPackageStatus.completed,
          createdAt: _createdAt,
          completedAt: DateTime.utc(2026, 9, 3),
          expiresAt: DateTime.utc(2026, 9, 20),
        ),
    );

    expect(
      find.byKey(const ValueKey('data-package-status-completed')),
      findsOneWidget,
    );
    expect(find.textContaining('went to the account'), findsOneWidget);
    expect(find.textContaining('expires 2026-09-20'), findsOneWidget);
    // A completed one can be asked for again.
    expect(find.byKey(const ValueKey('data-package-request')), findsOneWidget);
  });

  testWidgets('a failed request says why and can be asked again', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeDataPackage()
        ..package = AccountDataPackage(
          harvestId: '1234',
          status: DataPackageStatus.failed,
          createdAt: _createdAt,
          errorMessage: 'it broke',
        ),
    );

    expect(
      find.byKey(const ValueKey('data-package-status-failed')),
      findsOneWidget,
    );
    expect(find.textContaining('it broke'), findsOneWidget);
    expect(find.byKey(const ValueKey('data-package-request')), findsOneWidget);
  });

  testWidgets('a refusal is explained, not read as an outage', (tester) async {
    await _pump(tester, repository: _FakeDataPackage()..refuse = true);

    await tester.tap(find.byKey(const ValueKey('data-package-request')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('data-package-refused')), findsOneWidget);
    expect(find.textContaining('verified email address'), findsOneWidget);
    expect(find.byKey(const ValueKey('data-package-error')), findsNothing);
  });

  testWidgets('a failed read can be retried', (tester) async {
    await _pump(tester, repository: _FakeDataPackage()..failNextLoad = true);

    expect(find.byKey(const ValueKey('data-package-error')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('data-package-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('data-package-error')), findsNothing);
    expect(find.byKey(const ValueKey('data-package-none')), findsOneWidget);
  });

  testWidgets('the settings window offers the page and opens it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = UserSettingsController(() => null);
    addTearDown(settings.dispose);
    final data = AccountDataPackageController(() => null);
    addTearDown(data.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: UserSettingsDialog(
            controller: settings,
            dataPackageController: data,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-dataPackage')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-section-data-package')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('data-package-explainer')),
      findsOneWidget,
    );
  });

  testWidgets('a session with no account says why', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('settings-nav-dataPackage')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('user-data-package-unavailable')),
      findsOneWidget,
    );
  });
}

final class _FakeDataPackage implements AccountDataPackageRepository {
  AccountDataPackage? package;
  bool refuse = false;
  bool failNextLoad = false;
  bool requested = false;

  @override
  Future<AccountDataPackage?> loadLatest() async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    return package;
  }

  @override
  Future<AccountDataPackage?> request() async {
    requested = true;
    if (refuse) return null;
    return package ??
        AccountDataPackage(
          harvestId: '1234',
          status: DataPackageStatus.pending,
          createdAt: _createdAt,
        );
  }
}
