import 'dart:convert';

import 'package:flucord/src/application/auth_session_controller.dart';
import 'package:flucord/src/data/discord/discord_auth_session_repository.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

// TEST-NET-3, which exists so documentation can name an address without
// naming anybody's.
const _address = '203.0.113.7';

Map<String, Object?> _wireSession({
  String idHash = 'hash-1',
  Object? clientInfo = const {
    'platform': 'Discord Client',
    'os': 'Windows',
    'location': 'Berlin, Germany',
    'ip': _address,
  },
  bool current = false,
}) => {
  'id_hash': idHash,
  'approx_last_used_time': '2026-07-28T09:00:00+00:00',
  'client_info': clientInfo,
  if (current) 'is_current': true,
};

void main() {
  group('reading sessions', () {
    test('reads a session as the route states it', () {
      final sessions = DiscordAuthSessionRepository.readSessions({
        'user_sessions': [_wireSession(current: true)],
      });

      final session = sessions.single;
      expect(session.idHash, 'hash-1');
      expect(session.platform, 'Discord Client');
      expect(session.os, 'Windows');
      expect(session.location, 'Berlin, Germany');
      expect(session.ipAddress, _address);
      expect(session.lastUsedAt, DateTime.utc(2026, 7, 28, 9));
      expect(session.isCurrent, isTrue);
      expect(session.deviceLabel, 'Discord Client on Windows');
    });

    test('a bare list is read too', () {
      // Some builds serve the list without the wrapper.
      final sessions = DiscordAuthSessionRepository.readSessions([
        _wireSession(),
      ]);

      expect(sessions.single.idHash, 'hash-1');
      expect(sessions.single.isCurrent, isFalse);
    });

    test('a session with no hash is not a session', () {
      final sessions = DiscordAuthSessionRepository.readSessions({
        'user_sessions': [
          {
            'client_info': const {'os': 'Linux'},
          },
          'nonsense',
          _wireSession(),
        ],
      });

      expect(sessions.map((s) => s.idHash), ['hash-1']);
      expect(DiscordAuthSessionRepository.readSessions('nonsense'), isEmpty);
      expect(DiscordAuthSessionRepository.readSessions(null), isEmpty);
    });

    test('a session Discord described sparsely still names itself', () {
      final sparse = DiscordAuthSessionRepository.readSessions({
        'user_sessions': [
          {
            'id_hash': 'hash-2',
            'client_info': const {'os': 'Android'},
            'approx_last_used_time': 'not a time',
          },
        ],
      }).single;

      expect(sparse.deviceLabel, 'Android');
      expect(sparse.lastUsedAt, isNull);
      expect(sparse.location, isEmpty);

      final bare = DiscordAuthSessionRepository.readSessions({
        'user_sessions': [
          {'id_hash': 'hash-3', 'client_info': 'nonsense'},
        ],
      }).single;
      expect(bare.deviceLabel, 'Unknown device');

      final platformOnly = DiscordAuthSessionRepository.readSessions({
        'user_sessions': [
          {
            'id_hash': 'hash-4',
            'client_info': const {'platform': 'Discord Web'},
          },
        ],
      }).single;
      expect(platformOnly.deviceLabel, 'Discord Web');
    });

    test('a session compares by what it says', () {
      const session = AuthSession(idHash: 'h', platform: 'p');

      expect(session, const AuthSession(idHash: 'h', platform: 'p'));
      expect(
        session.hashCode,
        const AuthSession(idHash: 'h', platform: 'p').hashCode,
      );
      expect(session == const AuthSession(idHash: 'h'), isFalse);
      expect(session == Object(), isFalse);
    });
  });

  group('the routes', () {
    test('sessions are read from the auth route', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({
            'user_sessions': [_wireSession()],
          }),
        ),
      ]);

      final sessions = await _repository(transport).loadSessions();

      expect(sessions.single.idHash, 'hash-1');
      expect(transport.requests.single.uri.path, endsWith('/auth/sessions'));
    });

    test('ending sessions names every one in a single request', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);

      expect(
        await _repository(transport).endSessions(['hash-1', '', 'hash-2']),
        isTrue,
      );

      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, endsWith('/auth/sessions/logout'));
      // Blanks are dropped rather than sent as a session nobody has.
      expect(request.body, {
        'session_id_hashes': ['hash-1', 'hash-2'],
      });
    });

    test('ending nothing asks nothing', () async {
      final transport = _Transport([]);

      expect(await _repository(transport).endSessions(const []), isFalse);
      expect(await _repository(transport).endSessions(const ['']), isFalse);
      expect(transport.requests, isEmpty);
    });

    test('Discord wanting a password is a refusal, not a failure', () async {
      for (final status in [400, 401]) {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: status,
            headers: const {},
            body: jsonEncode({'message': 'Password required'}),
          ),
        ]);

        expect(
          await _repository(transport).endSessions(['hash-1']),
          isFalse,
          reason: '$status',
        );
      }
    });

    test('anything else is still an error', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 500,
          headers: const {},
          body: jsonEncode({'message': 'Server error'}),
        ),
      ]);

      await expectLater(
        _repository(transport).endSessions(['hash-1']),
        throwsA(isA<DiscordApiException>()),
      );
    });
  });

  group('the controller', () {
    test('loads once and again only when asked', () async {
      final repository = _FakeSessions();
      final controller = AuthSessionController(() => repository);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isTrue);
      await controller.load();
      await controller.load();
      expect(repository.loads, 1);

      await controller.load(refresh: true);
      expect(repository.loads, 2);
      expect(controller.sessions, hasLength(2));
      expect(controller.otherSessions.map((s) => s.idHash), ['hash-2']);
    });

    test('a transport with no session route does nothing', () async {
      final controller = AuthSessionController(() => null);
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isFalse);
      await controller.load();
      expect(await controller.endSession('hash-2'), isFalse);
      expect(controller.sessions, isEmpty);
      expect(controller.error, isNull);
    });

    test('a failed read is reported and can be retried', () async {
      final repository = _FakeSessions()..failNextLoad = true;
      final controller = AuthSessionController(() => repository);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.error, isA<StateError>());
      expect(controller.sessions, isEmpty);

      await controller.load();
      expect(controller.sessions, hasLength(2));
    });

    test('an ended session leaves after the list is re-read', () async {
      final repository = _FakeSessions();
      final controller = AuthSessionController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.endSession('hash-2'), isTrue);

      expect(repository.ended, [
        ['hash-2'],
      ]);
      // Re-read rather than patched: the route says it was accepted, not
      // which rows survived.
      expect(repository.loads, 2);
      expect(controller.sessions.map((s) => s.idHash), ['hash-1']);
    });

    test('signing out everywhere else spares this device', () async {
      final repository = _FakeSessions();
      final controller = AuthSessionController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.endOtherSessions(), isTrue);

      expect(repository.ended.single, ['hash-2']);
    });

    test('nothing to end is not a request', () async {
      final repository = _FakeSessions()..onlyCurrent = true;
      final controller = AuthSessionController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.endOtherSessions(), isFalse);
      expect(repository.ended, isEmpty);
    });

    test('a refusal is remembered as an answer', () async {
      final repository = _FakeSessions()..acceptEnd = false;
      final controller = AuthSessionController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.endSession('hash-2'), isFalse);

      expect(controller.wasEndRefused, isTrue);
      expect(controller.error, isNull);
      // The list is left alone, because nothing was ended.
      expect(controller.sessions, hasLength(2));
    });

    test('an end that could not be sent is an error', () async {
      final repository = _FakeSessions()..failNextEnd = true;
      final controller = AuthSessionController(() => repository);
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.endSession('hash-2'), isFalse);

      expect(controller.error, isA<StateError>());
      expect(controller.isEnding, isFalse);
    });

    test('disposing stops notifications', () async {
      final controller = AuthSessionController(_FakeSessions.new);
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..dispose();

      await controller.load();

      expect(notifications, 0);
    });
  });
}

DiscordAuthSessionRepository _repository(_Transport transport) =>
    DiscordAuthSessionRepository(
      DiscordRestClient(
        authorization: DiscordDesktopAuthorization('token'),
        transport: transport,
        baseUri: Uri.parse('https://discord.com/api/v9'),
      ),
    );

final class _FakeSessions implements AuthSessionRepository {
  int loads = 0;
  final List<List<String>> ended = [];
  bool acceptEnd = true;
  bool onlyCurrent = false;
  bool failNextLoad = false;
  bool failNextEnd = false;

  @override
  Future<List<AuthSession>> loadSessions() async {
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    loads++;
    if (onlyCurrent) {
      return const [AuthSession(idHash: 'hash-1', isCurrent: true)];
    }
    if (ended.isNotEmpty) {
      return const [AuthSession(idHash: 'hash-1', isCurrent: true)];
    }
    return const [
      AuthSession(idHash: 'hash-1', isCurrent: true),
      AuthSession(idHash: 'hash-2', platform: 'Discord Android'),
    ];
  }

  @override
  Future<bool> endSessions(List<String> idHashes) async {
    if (failNextEnd) {
      failNextEnd = false;
      throw StateError('end failed');
    }
    if (!acceptEnd) return false;
    ended.add(idHashes);
    return true;
  }
}

final class _Recorded {
  const _Recorded({required this.method, required this.uri, this.body});

  final String method;
  final Uri uri;
  final Map<String, Object?>? body;
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
    requests.add(
      _Recorded(
        method: method,
        uri: uri,
        body: body == null
            ? null
            : jsonDecode(utf8.decode(body)) as Map<String, Object?>,
      ),
    );
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
