import 'package:flucord/src/application/auth_session_controller.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/domain/auth_session.dart';
import 'package:flucord/src/presentation/widgets/user_settings_devices_section.dart';
import 'package:flucord/src/presentation/widgets/user_settings_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// TEST-NET-3: an address that belongs to documentation, not to anybody.
const _address = '203.0.113.7';

final _sessions = [
  AuthSession(
    idHash: 'hash-1',
    platform: 'Discord Client',
    os: 'Windows',
    isCurrent: true,
    lastUsedAt: DateTime.utc(2026, 7, 28, 9),
  ),
  const AuthSession(
    idHash: 'hash-2',
    platform: 'Discord Android',
    os: 'Android',
    location: 'Berlin, Germany',
    ipAddress: _address,
  ),
];

Future<AuthSessionController> _pump(
  WidgetTester tester, {
  AuthSessionRepository? repository,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = AuthSessionController(() => repository);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DevicesSettingsSection(controller: controller),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('every session is listed, with this one marked', (tester) async {
    await _pump(tester, repository: _FakeSessions(_sessions));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('device-hash-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('device-current-hash-1')), findsOneWidget);
    expect(find.text('Discord Client on Windows'), findsOneWidget);
    expect(find.text('Berlin, Germany · $_address'), findsOneWidget);
    expect(find.text('last used 2026-07-28'), findsOneWidget);
    // Ending this session is signing out, which lives elsewhere.
    expect(find.byKey(const ValueKey('device-end-hash-1')), findsNothing);
    expect(find.byKey(const ValueKey('device-end-hash-2')), findsOneWidget);
  });

  testWidgets('a session Discord described sparsely still renders', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeSessions(const [AuthSession(idHash: 'hash-9')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unknown device'), findsOneWidget);
    expect(find.text('Discord gave no details'), findsOneWidget);
  });

  testWidgets('one session is signed out from its own row', (tester) async {
    final repository = _FakeSessions(_sessions);
    await _pump(tester, repository: repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('device-end-hash-2')));
    await tester.pumpAndSettle();

    expect(repository.ended.single, ['hash-2']);
    expect(find.byKey(const ValueKey('device-hash-2')), findsNothing);
  });

  testWidgets('signing out everywhere else asks first', (tester) async {
    final repository = _FakeSessions(_sessions);
    await _pump(tester, repository: repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('devices-end-others')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('devices-confirm')), findsOneWidget);
    expect(
      find.text('1 other session will be ended. This one stays signed in.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.ended, isEmpty);

    await tester.tap(find.byKey(const ValueKey('devices-end-others')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('devices-confirm-accept')));
    await tester.pumpAndSettle();

    expect(repository.ended.single, ['hash-2']);
  });

  testWidgets('a refusal is explained rather than shown as a crash', (
    tester,
  ) async {
    await _pump(tester, repository: _FakeSessions(_sessions)..accept = false);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('device-end-hash-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('devices-refused')), findsOneWidget);
    expect(find.byKey(const ValueKey('devices-error')), findsNothing);
  });

  testWidgets('a read that failed offers a retry', (tester) async {
    await _pump(
      tester,
      repository: _FakeSessions(_sessions)..failFirstLoad = true,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('devices-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('devices-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('device-hash-1')), findsOneWidget);
  });

  testWidgets('an account Discord listed nothing for says so', (tester) async {
    await _pump(tester, repository: _FakeSessions(const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('devices-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('devices-end-others')), findsNothing);
  });

  testWidgets('the settings window offers the page and opens it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = UserSettingsController(() => null);
    addTearDown(settings.dispose);
    final sessions = AuthSessionController(() => _FakeSessions(_sessions));
    addTearDown(sessions.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: UserSettingsDialog(
            controller: settings,
            sessionController: sessions,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-nav-devices')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-section-devices')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('device-hash-2')), findsOneWidget);
  });

  testWidgets('a session with no route to list says why', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('settings-nav-devices')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('user-devices-unavailable')),
      findsOneWidget,
    );
  });
}

final class _FakeSessions implements AuthSessionRepository {
  _FakeSessions(this._sessions);

  final List<AuthSession> _sessions;
  final List<List<String>> ended = [];
  bool accept = true;
  bool failFirstLoad = false;

  @override
  Future<List<AuthSession>> loadSessions() async {
    if (failFirstLoad) {
      failFirstLoad = false;
      throw StateError('load failed');
    }
    if (ended.isEmpty) return _sessions;
    final gone = ended.expand((batch) => batch).toSet();
    return [
      for (final session in _sessions)
        if (!gone.contains(session.idHash)) session,
    ];
  }

  @override
  Future<bool> endSessions(List<String> idHashes) async {
    if (!accept) return false;
    ended.add(idHashes);
    return true;
  }
}
