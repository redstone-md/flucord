import 'package:flucord/src/application/account_connections_controller.dart';
import 'package:flucord/src/domain/account_connections.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flucord/src/presentation/widgets/user_settings_connections_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _spotify = AccountConnection(
  id: '120395',
  type: 'spotify',
  name: 'listener',
  verified: true,
  visibility: 1,
);

Future<AccountConnectionsController> _pump(
  WidgetTester tester, {
  AccountConnectionsRepository? repository,
  _RecordingLauncher? launcher,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = AccountConnectionsController(
    () => repository,
    launcher: launcher ?? _RecordingLauncher(),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConnectionsSettingsSection(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('lists what the account has linked', (tester) async {
    await _pump(
      tester,
      repository: _FakeConnections()..connections = [_spotify],
    );

    expect(
      find.byKey(const ValueKey('connection-spotify-120395')),
      findsOneWidget,
    );
    // One "Spotify" is the linked row, the other the link chip below.
    expect(find.text('Spotify'), findsNWidgets(2));
    expect(find.text('listener'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('connection-unlink-spotify')),
      findsOneWidget,
    );
  });

  testWidgets('says the link happens outside the app', (tester) async {
    await _pump(tester, repository: _FakeConnections());

    expect(
      find.byKey(const ValueKey('connections-disclaimer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('connections-link-services')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('connection-link-github')),
      findsOneWidget,
    );
  });

  testWidgets('unlinking a link takes the row away', (tester) async {
    final repository = _FakeConnections()..connections = [_spotify];
    final controller = await _pump(tester, repository: repository);

    await tester.tap(find.byKey(const ValueKey('connection-unlink-spotify')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('connection-spotify-120395')),
      findsNothing,
    );
    expect(repository.connections, isEmpty);
    expect(controller.unlinkRefusal, isNull);
  });

  testWidgets('a refused unlink is named, not read as an outage', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: _FakeConnections()
        ..connections = [_spotify]
        ..refuseUnlink = true,
    );

    await tester.tap(find.byKey(const ValueKey('connection-unlink-spotify')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('connections-unlink-refused')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('connection-spotify-120395')),
      findsOneWidget,
    );
  });

  testWidgets('a refused link names the service', (tester) async {
    final controller = await _pump(
      tester,
      repository: _FakeConnections()..linkUrl = null,
    );

    await tester.tap(find.byKey(const ValueKey('connection-link-reddit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('connections-link-refused')),
      findsOneWidget,
    );
    expect(controller.refusedService, 'reddit');
  });

  testWidgets('an account with nothing linked says so', (tester) async {
    await _pump(tester, repository: _FakeConnections());

    expect(find.byKey(const ValueKey('connections-none')), findsOneWidget);
  });

  testWidgets('a failed read can be retried', (tester) async {
    await _pump(tester, repository: _FakeConnections()..failNextLoad = true);

    expect(find.byKey(const ValueKey('connections-error')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('connections-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('connections-error')), findsNothing);
    expect(find.byKey(const ValueKey('connections-none')), findsOneWidget);
  });

  testWidgets('a revoked link says who revoked it', (tester) async {
    const revoked = AccountConnection(
      id: '765',
      type: 'steam',
      name: 'player',
      revoked: true,
    );
    await _pump(
      tester,
      repository: _FakeConnections()..connections = [revoked],
    );

    expect(
      find.byKey(const ValueKey('connection-status-steam')),
      findsOneWidget,
    );
    expect(find.textContaining('Access was revoked by Steam'), findsOneWidget);
  });
}

final class _FakeConnections implements AccountConnectionsRepository {
  List<AccountConnection> connections = const [];
  String? linkUrl = 'https://service.example.com/link';
  bool failNextLoad = false;
  bool refuseUnlink = false;

  @override
  Future<List<AccountConnection>> loadConnections() async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    return connections;
  }

  @override
  Future<String?> startLink(String type) async => linkUrl;

  @override
  Future<void> unlink(AccountConnection connection) async {
    if (refuseUnlink) {
      throw const AccountConnectionException(
        AccountConnectionFailure.unlinkRefused,
      );
    }
    connections = [
      for (final other in connections)
        if (other != connection) other,
    ];
  }
}

final class _RecordingLauncher implements ExternalLinkLauncher {
  @override
  Future<bool> open(Uri uri) async => true;
}
