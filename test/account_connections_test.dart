import 'dart:convert';

import 'package:flucord/src/application/account_connections_controller.dart';
import 'package:flucord/src/data/discord/discord_account_connections_repository.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/account_connections.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

const _spotify = AccountConnection(
  id: '120395',
  type: 'spotify',
  name: 'listener',
  verified: true,
  showActivity: true,
  visibility: 1,
);

void main() {
  group('reading the connections payload', () {
    test('reads what the account has linked', () {
      final connections = DiscordAccountConnectionsRepository.readConnections([
        {
          'id': '120395',
          'type': 'spotify',
          'name': 'listener',
          'verified': true,
          'revoked': false,
          'friend_sync': false,
          'show_activity': true,
          'two_way_link': false,
          'visibility': 1,
        },
        {'id': '765', 'type': 'steam', 'name': 'player', 'visibility': 0},
        // A row without the parts that name a link is dropped rather than
        // shown as a blank.
        {'type': 'nameless'},
      ]);

      expect(connections, hasLength(2));
      expect(connections.first, _spotify);
      expect(connections.first.hashCode, _spotify.hashCode);
      expect(connections.first.serviceName, 'Spotify');
      expect(connections.first.isPublic, isTrue);
      expect(connections[1].serviceName, 'Steam');
      expect(connections[1].isPublic, isFalse);
      expect(_spotify == Object(), isFalse);
    });

    test('a service name is capitalised from its own identifier', () {
      const connection = AccountConnection(
        id: '1',
        type: 'ebay_merchant',
        name: 'seller',
      );

      expect(connection.serviceName, 'Ebay Merchant');
    });
  });

  group('the routes', () {
    test('the list comes from the connections route', () async {
      final transport = _Transport([
        _response([
          {'id': '120395', 'type': 'spotify', 'name': 'listener'},
        ]),
      ]);

      final connections = await _repository(transport).loadConnections();

      expect(connections.single.type, 'spotify');
      expect(
        transport.requests.single.uri.path,
        endsWith('/users/@me/connections'),
      );
    });

    test('a link starts by asking where the service signs in', () async {
      final transport = _Transport([
        _response({'url': 'https://spotify.example.com/link?state=abc'}),
      ]);

      final url = await _repository(transport).startLink('spotify');

      expect(url, 'https://spotify.example.com/link?state=abc');
      expect(
        transport.requests.single.uri.path,
        endsWith('/connections/spotify/authorize'),
      );
      expect(
        transport.requests.single.uri.queryParameters,
        containsPair('two_way_link_type', 'desktop'),
      );
    });

    test(
      'a service Discord will not link answers null, not an error',
      () async {
        for (final status in [400, 403]) {
          final transport = _Transport([_error(status)]);
          expect(
            await _repository(transport).startLink('skype'),
            isNull,
            reason: '$status',
          );
        }
      },
    );

    test('a type with no name is not asked for', () async {
      final transport = _Transport([]);

      expect(await _repository(transport).startLink('  '), isNull);
      expect(transport.requests, isEmpty);
    });

    test('unlinking names the type and the account id', () async {
      final transport = _Transport([_error(204)]);

      await _repository(transport).unlink(_spotify);

      expect(
        transport.requests.single.uri.path,
        endsWith('/users/@me/connections/spotify/120395'),
      );
      expect(transport.requests.single.method, 'DELETE');
    });

    test('an unlink Discord does not hold is a plain refusal', () async {
      final transport = _Transport([_error(404)]);

      await expectLater(
        _repository(transport).unlink(_spotify),
        throwsA(isA<AccountConnectionException>()),
      );
    });

    test('anything else is still an error', () async {
      final transport = _Transport([_error(500)]);

      await expectLater(
        _repository(transport).unlink(_spotify),
        throwsA(isA<DiscordApiException>()),
      );
    });
  });

  group('the controller', () {
    test('lists what the account has linked', () async {
      final repository = _FakeConnections()..connections = [_spotify];
      final controller = AccountConnectionsController(
        () => repository,
        launcher: _RecordingLauncher(),
      );
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isTrue);
      await controller.load();

      expect(controller.connections.single, _spotify);
    });

    test('a transport offering none does nothing', () async {
      final controller = AccountConnectionsController(
        () => null,
        launcher: _RecordingLauncher(),
      );
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isFalse);
      await controller.load();
      expect(await controller.startLink('spotify'), isFalse);
      expect(controller.connections, isEmpty);
      expect(controller.error, isNull);
    });

    test('linking opens the service page outside the app', () async {
      final repository = _FakeConnections();
      final launcher = _RecordingLauncher();
      final controller = AccountConnectionsController(
        () => repository,
        launcher: launcher,
      );
      addTearDown(controller.dispose);

      expect(await controller.startLink('spotify'), isTrue);
      // The link is the service's to finish; its sign-in page opens in the
      // browser, never inside Flucord.
      expect(launcher.opened.single.toString(), repository.linkUrl);
      expect(controller.refusedService, isNull);
    });

    test(
      'a service Discord will not link is named, not read as an outage',
      () async {
        final controller = AccountConnectionsController(
          () => _FakeConnections()..linkUrl = null,
          launcher: _RecordingLauncher(),
        );
        addTearDown(controller.dispose);

        expect(await controller.startLink('skype'), isFalse);
        expect(controller.refusedService, 'skype');
        expect(controller.error, isNull);
      },
    );

    test('unlinking removes the row', () async {
      final repository = _FakeConnections()..connections = [_spotify];
      final controller = AccountConnectionsController(
        () => repository,
        launcher: _RecordingLauncher(),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(await controller.unlink(_spotify), isTrue);
      expect(controller.connections, isEmpty);
    });

    test('an unlink Discord refused is named, not read as an outage', () async {
      final repository = _FakeConnections()
        ..connections = [_spotify]
        ..refuseUnlink = true;
      final controller = AccountConnectionsController(
        () => repository,
        launcher: _RecordingLauncher(),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(await controller.unlink(_spotify), isFalse);

      expect(controller.connections, hasLength(1));
      expect(controller.unlinkRefusal, 'Spotify');
      expect(controller.error, isNull);
    });

    test('a failed read is reported and can be retried', () async {
      final repository = _FakeConnections()
        ..failNextLoad = true
        ..connections = [_spotify];
      final controller = AccountConnectionsController(
        () => repository,
        launcher: _RecordingLauncher(),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.error, isA<StateError>());

      await controller.load(refresh: true);
      expect(controller.connections.single, _spotify);
    });

    test('a link that could not be sent is an error', () async {
      final controller = AccountConnectionsController(
        () => _FakeConnections()..failNextLink = true,
        launcher: _RecordingLauncher(),
      );
      addTearDown(controller.dispose);

      expect(await controller.startLink('spotify'), isFalse);
      expect(controller.error, isA<StateError>());
    });

    test('disposing stops notifications', () async {
      final controller = AccountConnectionsController(
        _FakeConnections.new,
        launcher: _RecordingLauncher(),
      );
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..dispose();

      await controller.load();

      expect(notifications, 0);
    });
  });
}

DiscordAccountConnectionsRepository _repository(_Transport transport) =>
    DiscordAccountConnectionsRepository(
      DiscordRestClient(
        authorization: DiscordDesktopAuthorization('token'),
        transport: transport,
        baseUri: Uri.parse('https://discord.com/api/v9'),
      ),
    );

final class _FakeConnections implements AccountConnectionsRepository {
  List<AccountConnection> connections = const [];
  String? linkUrl = 'https://spotify.example.com/link?state=abc';
  bool failNextLoad = false;
  bool failNextLink = false;
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
  Future<String?> startLink(String type) async {
    if (failNextLink) {
      failNextLink = false;
      throw StateError('link failed');
    }
    return linkUrl;
  }

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

DiscordHttpResponse _response(Object payload) => DiscordHttpResponse(
  statusCode: 200,
  headers: const {},
  body: jsonEncode(payload),
);

DiscordHttpResponse _error(int status) => DiscordHttpResponse(
  statusCode: status,
  headers: const {},
  body: jsonEncode({'message': 'Refused'}),
);

final class _RecordingLauncher implements ExternalLinkLauncher {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

final class _Transport implements DiscordHttpTransport {
  _Transport(this._responses);

  final List<DiscordHttpResponse> _responses;
  final List<_Recorded> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(_Recorded(method, uri));
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}

final class _Recorded {
  const _Recorded(this.method, this.uri);

  final String method;
  final Uri uri;
}
