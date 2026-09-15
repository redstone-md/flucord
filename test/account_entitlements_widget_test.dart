import 'package:flucord/src/application/account_entitlements_controller.dart';
import 'package:flucord/src/domain/account_entitlements.dart';
import 'package:flucord/src/presentation/widgets/user_settings_entitlements_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AccountEntitlementsController> _pump(
  WidgetTester tester, {
  AccountEntitlementsRepository? repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = AccountEntitlementsController(() => repository);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: EntitlementsSettingsSection(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('names the tier, the boosts, and what they change', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeEntitlements());

    // One "Nitro" names the tier in the row, the other names the grant.
    expect(find.text('Nitro'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('entitlements-boosts')), findsOneWidget);
    expect(find.text('2 server boosts held.'), findsOneWidget);
    expect(find.text('Bigger uploads.'), findsOneWidget);
    expect(find.byKey(const ValueKey('entitlement-1')), findsOneWidget);
  });

  testWidgets('says the page only reports what is held', (tester) async {
    await _pump(tester, repository: _FakeEntitlements());

    expect(
      find.byKey(const ValueKey('entitlements-disclaimer')),
      findsOneWidget,
    );
  });

  testWidgets('an account holding nothing says so', (tester) async {
    await _pump(
      tester,
      repository: _FakeEntitlements()..held = const AccountEntitlements(),
    );

    expect(find.text('No Nitro'), findsOneWidget);
    expect(find.byKey(const ValueKey('entitlements-none')), findsOneWidget);
  });

  testWidgets('a failed read can be retried', (tester) async {
    await _pump(tester, repository: _FakeEntitlements()..failNextLoad = true);

    expect(find.byKey(const ValueKey('entitlements-error')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('entitlements-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('entitlements-error')), findsNothing);
    expect(find.text('Nitro'), findsNWidgets(2));
  });

  testWidgets('a grant that expires names the day', (tester) async {
    await _pump(
      tester,
      repository: _FakeEntitlements(
        grants: const [
          AccountEntitlement(
            id: '12',
            label: 'Server Boost',
            heldUntil: null,
            isBoost: true,
          ),
        ],
      ),
    );

    expect(find.text('Does not expire.'), findsOneWidget);
  });
}

final class _FakeEntitlements implements AccountEntitlementsRepository {
  AccountEntitlements held = const AccountEntitlements(
    premiumTier: PremiumTier.nitro,
    boostsHeld: 2,
    entitlements: [
      AccountEntitlement(id: '1', label: 'Nitro'),
      AccountEntitlement(id: '2', label: 'Server Boost', isBoost: true),
      AccountEntitlement(id: '3', label: 'Server Boost', isBoost: true),
    ],
  );
  bool failNextLoad = false;

  _FakeEntitlements({List<AccountEntitlement> grants = const []}) {
    if (grants.isNotEmpty) {
      held = AccountEntitlements(
        boostsHeld: grants.where((grant) => grant.isBoost).length,
        entitlements: grants,
      );
    }
  }

  @override
  Future<AccountEntitlements> loadEntitlements() async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    return held;
  }
}
