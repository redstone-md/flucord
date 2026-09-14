import 'package:flucord/src/application/account_standing_controller.dart';
import 'package:flucord/src/domain/account_standing.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/presentation/widgets/user_settings_dialog.dart';
import 'package:flucord/src/presentation/widgets/user_settings_standing_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _standing = AccountStanding(
  username: 'mira',
  standing: 100,
  isDsaEligible: true,
  classifications: [
    AccountClassification(
      id: 'record-1',
      title: 'Harassment',
      subtitle: 'A message was removed',
      appealEligible: true,
    ),
    AccountClassification(id: 'record-2', title: 'Spam', guildId: 'guild-1'),
    AccountClassification(id: 'record-3'),
  ],
);

Future<AccountStandingController> _pump(
  WidgetTester tester, {
  SafetyHubRepository? repository,
}) async {
  final controller = AccountStandingController(() => repository);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AccountStandingSection(controller: controller),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('a suspended account is told so, and can appeal once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeSafetyHub(const AccountStanding())
      ..suspension = const AccountSuspension(
        isSuspended: true,
        reason: 'Harassment',
        classificationId: 'record-1',
        canRequestReview: true,
      );
    final controller = AccountStandingController(() => repository);
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountStandingSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('account-suspended')), findsOneWidget);
    expect(find.text('Harassment'), findsOneWidget);
    // An absent end is said rather than left blank: it is not "today".
    expect(find.textContaining('has not said when it ends'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('account-suspended-appeal')));
    await tester.pumpAndSettle();

    expect(repository.suspendedReviews, ['record-1']);
    expect(find.text('Review requested'), findsOneWidget);
  });

  testWidgets('a suspension that says when it ends shows the date', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _FakeSafetyHub(const AccountStanding())
      ..suspension = AccountSuspension(
        isSuspended: true,
        endsAt: DateTime.utc(2026, 8),
      );
    final controller = AccountStandingController(() => repository);
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountStandingSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Until'), findsOneWidget);
    // No record to appeal, so no button offering one.
    expect(
      find.byKey(const ValueKey('account-suspended-appeal')),
      findsNothing,
    );
  });

  testWidgets('the page shows every record, split by what it is against', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeSafetyHub(_standing));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('standing-username')), findsOneWidget);
    expect(find.text('Against this account'), findsOneWidget);
    expect(find.text('Against servers you own'), findsOneWidget);
    expect(find.byKey(const ValueKey('standing-record-record-1')), findsOne);
    expect(find.byKey(const ValueKey('standing-record-record-2')), findsOne);
    expect(find.text('Harassment'), findsOneWidget);
    expect(find.text('A message was removed'), findsOneWidget);
    // A record Discord sent no words for still renders as a record rather
    // than as a blank row.
    expect(find.text('Recorded action'), findsOneWidget);
    expect(find.byKey(const ValueKey('standing-dsa')), findsOneWidget);
  });

  testWidgets('an account with nothing on record says so', (tester) async {
    await _pump(
      tester,
      repository: _FakeSafetyHub(const AccountStanding(username: 'mira')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('standing-clear')), findsOneWidget);
    expect(find.text('Against this account'), findsNothing);
  });

  testWidgets('a review is asked for once and then reported as asked', (
    tester,
  ) async {
    final repository = _FakeSafetyHub(_standing);
    await _pump(tester, repository: repository);
    await tester.pumpAndSettle();

    // Only the eligible record offers it.
    expect(find.byKey(const ValueKey('standing-review-record-1')), findsOne);
    expect(
      find.byKey(const ValueKey('standing-review-record-2')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('standing-review-record-1')));
    await tester.pumpAndSettle();

    expect(repository.reviews, ['record-1']);
    expect(find.byKey(const ValueKey('standing-requested-record-1')), findsOne);
    expect(
      find.byKey(const ValueKey('standing-review-record-1')),
      findsNothing,
    );
  });

  testWidgets('a review Discord declines reads as an answer', (tester) async {
    final repository = _FakeSafetyHub(_standing)..accept = false;
    await _pump(tester, repository: repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('standing-review-record-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('standing-refused-record-1')), findsOne);
    // Not an error banner: Discord saying no is not the client failing.
    expect(find.byKey(const ValueKey('standing-error')), findsNothing);
  });

  testWidgets('a read that failed offers a retry', (tester) async {
    final repository = _FakeSafetyHub(_standing)..failFirstLoad = true;
    await _pump(tester, repository: repository);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('standing-error')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('standing-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('standing-username')), findsOneWidget);
  });

  testWidgets('checking again re-reads the record', (tester) async {
    final repository = _FakeSafetyHub(_standing);
    await _pump(tester, repository: repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('standing-refresh')));
    await tester.pumpAndSettle();

    expect(repository.loads, 2);
  });

  testWidgets('the settings window offers the page and opens it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = UserSettingsController(() => null);
    addTearDown(settings.dispose);
    final standing = AccountStandingController(() => _FakeSafetyHub(_standing));
    addTearDown(standing.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: UserSettingsDialog(
            controller: settings,
            standingController: standing,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-nav-standing')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-section-standing')),
      findsOneWidget,
    );
    // The record is read even though this session has no settings store: the
    // safety hub is its own route, and gating it on settings would hide it.
    expect(find.byKey(const ValueKey('standing-record-record-1')), findsOne);
  });

  testWidgets('a session with no safety hub says why the page is empty', (
    tester,
  ) async {
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
    await tester.tap(find.byKey(const ValueKey('settings-nav-standing')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('user-standing-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets('a transport with no safety hub shows nothing to retry', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('standing-error')), findsNothing);
    expect(find.byKey(const ValueKey('standing-clear')), findsNothing);
    expect(find.byKey(const ValueKey('standing-loading')), findsNothing);
  });
}

final class _FakeSafetyHub implements SafetyHubRepository {
  AccountSuspension suspension = AccountSuspension.none;
  final List<String> suspendedReviews = [];
  bool acceptSuspendedReview = true;

  @override
  Future<AccountSuspension> loadSuspension() async => suspension;

  @override
  Future<bool> requestSuspendedReview(String classificationId) async {
    suspendedReviews.add(classificationId);
    return acceptSuspendedReview;
  }

  _FakeSafetyHub(this._standing);

  final AccountStanding _standing;
  final List<String> reviews = [];
  int loads = 0;
  bool accept = true;
  bool failFirstLoad = false;

  @override
  Future<AccountStanding> loadAccountStanding() async {
    if (failFirstLoad) {
      failFirstLoad = false;
      throw StateError('load failed');
    }
    loads++;
    return _standing;
  }

  @override
  Future<bool> requestReview(String classificationId) async {
    if (!accept) return false;
    reviews.add(classificationId);
    return true;
  }
}
