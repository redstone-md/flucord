import 'package:flucord/src/application/family_centre_controller.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/domain/family_centre.dart';
import 'package:flucord/src/presentation/widgets/user_settings_dialog.dart';
import 'package:flucord/src/presentation/widgets/user_settings_family_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _family = FamilyCentre(
  ageGroup: 'TEEN',
  linkedUserIds: ['parent-1'],
  userNames: {'parent-1': 'Ada', 'friend-1': 'mira'},
  activity: TeenActivitySummary(
    teenUserId: 'teen-1',
    totals: {'messages': 12},
    userIds: ['friend-1'],
    guildIds: ['guild-1'],
  ),
);

Future<FamilyCentreController> _pump(
  WidgetTester tester, {
  FamilyCentreRepository? repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = FamilyCentreController(() => repository);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: FamilyCentreSection(controller: controller),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('the page shows who is linked and the counts', (tester) async {
    await _pump(tester, repository: _FakeFamilyCentre(_family));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('family-age-group')), findsOneWidget);
    expect(find.byKey(const ValueKey('family-linked-parent-1')), findsOne);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byKey(const ValueKey('family-total-messages')), findsOne);
    expect(find.text('messages: 12'), findsOneWidget);
    // Said plainly, so nobody has to guess whether this shows messages.
    expect(
      find.text('Counts only. Discord reports how much, never what was said.'),
      findsOneWidget,
    );
    expect(find.text('People: mira'), findsOneWidget);
    expect(find.text('1 server'), findsOneWidget);
  });

  testWidgets('an account with nobody linked says so', (tester) async {
    await _pump(
      tester,
      repository: _FakeFamilyCentre(const FamilyCentre(ageGroup: 'ADULT')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('family-none-linked')), findsOneWidget);
    expect(find.byKey(const ValueKey('family-activity')), findsNothing);
  });

  testWidgets('a link code is asked for and then forgotten', (tester) async {
    final controller = await _pump(
      tester,
      repository: _FakeFamilyCentre(_family),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('family-link-code')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('family-request-code')));
    await tester.pumpAndSettle();

    expect(find.text('ABC-123'), findsOneWidget);

    // Leaving the page drops the code: it lets a parent see this account.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(controller.linkCode, isNull);
  });

  testWidgets('an account Discord will not issue a code for is told', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeFamilyCentre(_family)..issueCode = false,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('family-request-code')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('family-link-refused')), findsOneWidget);
    expect(find.byKey(const ValueKey('family-error')), findsNothing);
  });

  testWidgets('a read that failed offers a retry', (tester) async {
    await _pump(
      tester,
      repository: _FakeFamilyCentre(_family)..failFirstLoad = true,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('family-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('family-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('family-linked-parent-1')), findsOne);
  });

  testWidgets('a transport with none renders nothing to act on', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('family-error')), findsNothing);
    expect(find.byKey(const ValueKey('family-loading')), findsNothing);
    expect(find.byKey(const ValueKey('family-none-linked')), findsNothing);
  });

  testWidgets('the settings window offers the page and opens it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = UserSettingsController(() => null);
    addTearDown(settings.dispose);
    final family = FamilyCentreController(() => _FakeFamilyCentre(_family));
    addTearDown(family.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: UserSettingsDialog(
            controller: settings,
            familyController: family,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-family')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-section-family')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('family-linked-parent-1')), findsOne);
  });

  testWidgets('a session with no family centre says why', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('settings-nav-family')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('user-family-unavailable')),
      findsOneWidget,
    );
  });
}

final class _FakeFamilyCentre implements FamilyCentreRepository {
  final Map<String, TeenControls> teenControls = {};
  final List<String> teenReads = [];
  Object? teenFailure;

  @override
  Future<TeenControls> loadTeenControls(String teenId) async {
    teenReads.add(teenId);
    if (teenFailure case final error?) throw error;
    return teenControls[teenId] ?? TeenControls(userId: teenId);
  }

  _FakeFamilyCentre(this._family);

  final FamilyCentre _family;
  bool issueCode = true;
  bool failFirstLoad = false;

  @override
  Future<FamilyCentre> loadFamilyCentre() async {
    if (failFirstLoad) {
      failFirstLoad = false;
      throw StateError('load failed');
    }
    return _family;
  }

  @override
  Future<String?> requestLinkCode() async => issueCode ? 'ABC-123' : null;
}
