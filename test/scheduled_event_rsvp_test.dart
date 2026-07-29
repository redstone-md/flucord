import 'dart:convert';

import 'package:flucord/src/data/discord/discord_desktop_api_client.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/data/discord/discord_desktop_chat_repository.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_client.dart';
import 'package:flucord/src/data/discord/discord_desktop_websocket.dart';
import 'package:flucord/src/data/sqlite_chat_cache.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _guild = '111111111111111111';
const _event = '222222222222222222';
const _exception = '333333333333333333';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('being interested is a put carrying Discord\'s own response', () async {
    final transport = _Transport();

    await _client(transport).setGuildScheduledEventInterest(
      guildId: _guild,
      eventId: _event,
      interested: true,
    );

    final request = transport.requests.single;
    expect(request.method, 'PUT');
    expect(
      request.uri.path,
      endsWith('/guilds/$_guild/scheduled-events/$_event/users/@me'),
    );
    expect(request.body, {'response': 1});
  });

  test('taking it back sends no body at all', () async {
    final transport = _Transport();

    await _client(transport).setGuildScheduledEventInterest(
      guildId: _guild,
      eventId: _event,
      interested: false,
    );

    final request = transport.requests.single;
    expect(request.method, 'DELETE');
    // The absent body is how Discord tells the two apart on one route.
    expect(request.body, isNull);
  });

  test('one occurrence of a recurring event names itself', () async {
    final transport = _Transport();

    await _client(transport).setGuildScheduledEventInterest(
      guildId: _guild,
      eventId: _event,
      interested: true,
      exceptionId: _exception,
    );

    expect(
      transport.requests.single.uri.path,
      endsWith(
        '/guilds/$_guild/scheduled-events/$_event/$_exception/users/@me',
      ),
    );
  });

  test(
    'an empty occurrence is the event itself, not a path with a gap',
    () async {
      final transport = _Transport();

      await _client(transport).setGuildScheduledEventInterest(
        guildId: _guild,
        eventId: _event,
        interested: true,
        exceptionId: '',
      );

      expect(
        transport.requests.single.uri.path,
        endsWith('/guilds/$_guild/scheduled-events/$_event/users/@me'),
      );
    },
  );

  group('the desktop repository', () {
    test('reads the guild events with their counts', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode([
            {
              'id': _event,
              'guild_id': _guild,
              'name': 'Forge night',
              'scheduled_start_time': '2026-08-01T18:00:00+00:00',
              'entity_type': 3,
              'status': 1,
              'user_count': 4,
            },
            'nonsense',
          ]),
        ),
      ]);

      final events = await (await _repository(
        transport,
      )).loadScheduledEvents(_guild);

      expect(events.single.name, 'Forge night');
      expect(events.single.interestedCount, 4);
      expect(
        transport.requests.single.uri.path,
        endsWith('/guilds/$_guild/scheduled-events'),
      );
      // The count is what the button sits beside, so it is asked for.
      expect(
        transport.requests.single.uri.queryParameters['with_user_count'],
        'true',
      );
    });

    test('an RSVP that Discord took answers yes', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);

      expect(
        await (await _repository(
          transport,
        )).setEventInterest(spaceId: _guild, eventId: _event, interested: true),
        isTrue,
      );

      expect(transport.requests.single.method, 'PUT');
    });

    test('an event that will not take one answers no', () async {
      for (final status in [400, 403]) {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: status,
            headers: const {},
            body: jsonEncode({'message': 'Event has ended'}),
          ),
        ]);

        expect(
          await (await _repository(transport)).setEventInterest(
            spaceId: _guild,
            eventId: _event,
            interested: false,
          ),
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
        (await _repository(
          transport,
        )).setEventInterest(spaceId: _guild, eventId: _event, interested: true),
        throwsA(isA<DiscordApiException>()),
      );
    });
  });

  group('managing events', () {
    test('the interested list names people as the server knows them', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode([
            {
              'user': {
                'id': 'user-1',
                'username': 'mira',
                'global_name': 'Mira',
              },
              'member': {'nick': 'Forge Mira'},
            },
            {
              'user': {'id': 'user-2', 'global_name': 'Ada'},
            },
            {
              'user': {'id': 'user-3', 'username': 'lena'},
            },
            {
              'user': {'id': 'user-4'},
            },
            {'no': 'user'},
            'nonsense',
          ]),
        ),
      ]);

      final attendees = await (await _repository(
        transport,
      )).loadEventAttendees(spaceId: _guild, eventId: _event);

      // The server nickname wins: it is the name everybody else there sees.
      expect(attendees.map((who) => who.label), [
        'Forge Mira',
        'Ada',
        'lena',
        'user-4',
      ]);
      final request = transport.requests.single;
      expect(
        request.uri.path,
        endsWith('/guilds/$_guild/scheduled-events/$_event/users'),
      );
      // with_member is what brings the nickname back at all.
      expect(request.uri.queryParameters['with_member'], 'true');
      expect(request.uri.queryParameters['limit'], '100');
    });

    test('the limit is clamped to what Discord will serve', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode(const <Object?>[]),
        ),
      ]);

      await (await _repository(
        transport,
      )).loadEventAttendees(spaceId: _guild, eventId: _event, limit: 500);

      expect(transport.requests.single.uri.queryParameters['limit'], '100');
    });

    test(
      'a create sends the whole event and reads back what was stored',
      () async {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: 200,
            headers: const {},
            body: jsonEncode({
              'id': _event,
              'guild_id': _guild,
              'name': 'Forge night',
              'scheduled_start_time': '2026-08-01T18:00:00.000Z',
              'entity_type': 3,
              'status': 1,
            }),
          ),
        ]);

        final created = await (await _repository(transport))
            .createScheduledEvent(
              spaceId: _guild,
              draft: GuildScheduledEventDraft(
                name: 'Forge night',
                startTime: DateTime.utc(2026, 8, 1, 18),
                endTime: DateTime.utc(2026, 8, 1, 20),
                entityType: GuildScheduledEventEntityType.external,
                location: 'The workshop',
              ),
            );

        expect(created!.name, 'Forge night');
        final request = transport.requests.single;
        expect(request.method, 'POST');
        expect(request.uri.path, endsWith('/guilds/$_guild/scheduled-events'));
        expect(request.body?['entity_type'], 3);
        expect(request.body?['privacy_level'], 2);
      },
    );

    test('a draft Discord would refuse is never sent', () async {
      final transport = _Transport();

      final created = await (await _repository(transport)).createScheduledEvent(
        spaceId: _guild,
        draft: GuildScheduledEventDraft(
          name: '',
          startTime: DateTime.utc(2026, 8, 1, 18),
          entityType: GuildScheduledEventEntityType.external,
        ),
      );

      expect(created, isNull);
      expect(transport.requests, isEmpty);
    });

    test('an edit patches only what it carries', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({
            'id': _event,
            'guild_id': _guild,
            'name': 'Renamed',
            'scheduled_start_time': '2026-08-01T18:00:00.000Z',
            'entity_type': 3,
            'status': 1,
          }),
        ),
      ]);
      final edit = GuildScheduledEventEdit()..name = 'Renamed';

      final updated = await (await _repository(
        transport,
      )).editScheduledEvent(spaceId: _guild, eventId: _event, edit: edit);

      expect(updated!.name, 'Renamed');
      expect(transport.requests.single.method, 'PATCH');
      expect(transport.requests.single.body, {'name': 'Renamed'});
    });

    test('an empty edit is not a request', () async {
      final transport = _Transport();

      expect(
        await (await _repository(transport)).editScheduledEvent(
          spaceId: _guild,
          eventId: _event,
          edit: GuildScheduledEventEdit(),
        ),
        isNull,
      );
      expect(transport.requests, isEmpty);
    });

    test('a delete answers whether it happened', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);

      expect(
        await (await _repository(
          transport,
        )).deleteScheduledEvent(spaceId: _guild, eventId: _event),
        isTrue,
      );
      expect(transport.requests.single.method, 'DELETE');
    });

    test('an event already gone, or not ours, answers no', () async {
      for (final status in [403, 404]) {
        final transport = _Transport([
          DiscordHttpResponse(
            statusCode: status,
            headers: const {},
            body: jsonEncode({'message': 'Unknown event'}),
          ),
        ]);

        expect(
          await (await _repository(
            transport,
          )).deleteScheduledEvent(spaceId: _guild, eventId: _event),
          isFalse,
          reason: '$status',
        );
      }
    });

    test('anything else on a delete is still an error', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 500,
          headers: const {},
          body: jsonEncode({'message': 'Server error'}),
        ),
      ]);

      await expectLater(
        (await _repository(
          transport,
        )).deleteScheduledEvent(spaceId: _guild, eventId: _event),
        throwsA(isA<DiscordApiException>()),
      );
    });
  });
}

DiscordDesktopApiClient _client(_Transport transport) =>
    DiscordDesktopApiClient(
      authorization: 'token',
      headers: const {},
      transport: transport,
      baseUri: Uri.parse('https://discord.com/api/v9'),
    );

final class _Recorded {
  const _Recorded({required this.method, required this.uri, this.body});

  final String method;
  final Uri uri;
  final Map<String, Object?>? body;
}

final class _Transport implements DiscordHttpTransport {
  _Transport([this._responses = const []]);

  /// What to answer with, in order. The RSVP routes answer 204 with no body,
  /// so a transport given nothing answers that.
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
    if (_responses.isEmpty) {
      return const DiscordHttpResponse(statusCode: 204, headers: {}, body: '');
    }
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}

Future<DiscordDesktopChatRepository> _repository(_Transport transport) async {
  final cache = await SqliteChatCache.openAt(
    inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  final repository = DiscordDesktopChatRepository(
    _client(transport),
    DiscordDesktopGatewayClient(
      authorization: 'account-session',
      properties: const {'os': 'Windows'},
      // Never connected: these tests are about two REST routes, and the
      // repository only needs a gateway to exist.
      socketConnector: _UnusedConnector(),
    ),
    cache,
  );
  addTearDown(repository.close);
  return repository;
}

final class _UnusedConnector implements DiscordDesktopWebSocketConnector {
  @override
  Future<DiscordDesktopWebSocket> connect(
    Uri uri, {
    Map<String, String> headers = const {},
  }) => throw StateError('These tests never open the gateway');
}
