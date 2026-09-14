part of 'guild_management_repository_test.dart';

/// The server-access routes, checked against the wire shape the desktop
/// session sends and receives: the invite preview, the join, the create, and
/// the leave, plus the hydration reads a join makes before the answer goes
/// out.
void _serverAccessCases() {
  group('server access', () {
    test('previews an invite with its counts', () async {
      final transport = _Transport([
        _json({
          'code': 'aurora',
          'guild': {
            'id': '444444444444444444',
            'name': 'Aurora Labs',
            'icon': 'aabbcc',
            'description': 'Research chat',
          },
          'channel': {'id': '500000000000000001', 'name': 'general'},
          'approximate_member_count': 1204,
        }),
      ]);
      final preview = await _repository(transport).previewInvite('aurora');

      expect(preview.code, 'aurora');
      expect(preview.name, 'Aurora Labs');
      expect(preview.guildId, '444444444444444444');
      expect(preview.approximateMemberCount, 1204);
      expect(preview.channelName, 'general');
      expect(preview.iconUrl, contains('/icons/444444444444444444/'));
      expect(transport.requests.single.uri.path, endsWith('/invites/aurora'));
      expect(
        transport.requests.single.uri.queryParameters['with_counts'],
        'true',
      );
    });

    test('an unknown invite refuses as invalid, not as a fault', () async {
      final transport = _Transport([
        const DiscordHttpResponse(
          statusCode: 404,
          headers: {},
          body: '{"message": "Unknown Invite", "code": 1006}',
        ),
      ]);
      expect(
        () => _repository(transport).previewInvite('gone'),
        throwsA(
          isA<GuildAccessException>()
              .having(
                (error) => error.refusal,
                'refusal',
                GuildAccessRefusal.invalid,
              )
              .having((error) => error.message, 'message', isNotEmpty),
        ),
      );
    });

    test('an expired invite says so in the preview, before the join', () async {
      final expired = _Transport([
        const DiscordHttpResponse(
          statusCode: 404,
          headers: {},
          body: '{"message": "Invite Expired", "code": 1007}',
        ),
      ]);
      expect(
        () => _repository(expired).previewInvite('stale'),
        throwsA(
          isA<GuildAccessException>()
              .having(
                (error) => error.refusal,
                'refusal',
                GuildAccessRefusal.expired,
              )
              .having(
                (error) => error.message,
                'message',
                'This invite has expired.',
              ),
        ),
      );

      // A 404 that does not name expiry still reads as invalid: the two
      // answers say different things and the card should not guess.
      final unknown = _Transport([
        const DiscordHttpResponse(
          statusCode: 404,
          headers: {},
          body: '{"message": "Unknown Invite", "code": 1006}',
        ),
      ]);
      expect(
        () => _repository(unknown).previewInvite('gone'),
        throwsA(
          isA<GuildAccessException>().having(
            (error) => error.refusal,
            'refusal',
            GuildAccessRefusal.invalid,
          ),
        ),
      );
    });

    test('joins and hydrates the gained guild', () async {
      final transport = _Transport([
        _json({'id': '444444444444444444', 'name': 'Aurora Labs'}),
        _json({
          'id': '444444444444444444',
          'name': 'Aurora Labs',
          'icon': 'aabbcc',
          'owner_id': '987654321098765432',
        }),
        _json([
          {
            'id': '444444444444444444',
            'type': 4,
            'name': 'Research',
            'position': 0,
          },
          {
            'id': '500000000000000001',
            'type': 0,
            'name': 'general',
            'position': 0,
          },
          {
            'id': '500000000000000002',
            'type': 2,
            'name': 'lab-notes',
            'position': 1,
          },
        ]),
        _json([
          {
            'id': '444444444444444444',
            'name': '@everyone',
            'position': 0,
            'permissions': '1024',
          },
        ]),
        _json({
          'user': {'id': '987654321098765432', 'username': 'mira'},
          'roles': [],
        }),
      ]);
      final gained = await _FakeSinkingRepository(
        transport,
      ).joinGuild('aurora');

      expect(gained.space.name, 'Aurora Labs');
      expect(gained.space.iconUrl, isNotNull);
      expect(gained.channels.map((channel) => channel.name), [
        'general',
        'lab-notes',
      ]);
      expect(gained.categories.single.name, 'Research');
      expect(gained.roles.single.name, '@everyone');
      expect(gained.members.single.id, '987654321098765432');
      expect(transport.requests.first.uri.path, endsWith('/invites/aurora'));
      expect(transport.requests.first.method, 'POST');
      // The hydration reads that follow: the guild, its channels, its roles,
      // and this account's own membership.
      expect(
        transport.requests[1].uri.path,
        endsWith('/guilds/444444444444444444'),
      );
      expect(
        transport.requests[2].uri.path,
        endsWith('/guilds/444444444444444444/channels'),
      );
      expect(
        transport.requests[3].uri.path,
        endsWith('/guilds/444444444444444444/roles'),
      );
      expect(
        transport.requests[4].uri.path,
        endsWith('/guilds/444444444444444444/members/@me'),
      );
    });

    test('a join the account is already in refuses plainly', () async {
      final transport = _Transport([
        const DiscordHttpResponse(
          statusCode: 403,
          headers: {},
          body: '{"message": "You are already in this guild.", "code": 40002}',
        ),
      ]);
      expect(
        () => _repository(transport).joinGuild('aurora'),
        throwsA(
          isA<GuildAccessException>().having(
            (error) => error.refusal,
            'refusal',
            GuildAccessRefusal.alreadyJoined,
          ),
        ),
      );
    });

    test('an expired invite and an unknown one read differently', () async {
      final expired = _Transport([
        const DiscordHttpResponse(
          statusCode: 404,
          headers: {},
          body: '{"message": "Invite expired", "code": 1007}',
        ),
      ]);
      expect(
        () => _repository(expired).joinGuild('aurora'),
        throwsA(
          isA<GuildAccessException>().having(
            (error) => error.refusal,
            'refusal',
            GuildAccessRefusal.expired,
          ),
        ),
      );

      final unknown = _Transport([
        const DiscordHttpResponse(
          statusCode: 404,
          headers: {},
          body: '{"message": "Unknown Invite", "code": 1006}',
        ),
      ]);
      expect(
        () => _repository(unknown).joinGuild('aurora'),
        throwsA(
          isA<GuildAccessException>().having(
            (error) => error.refusal,
            'refusal',
            GuildAccessRefusal.invalid,
          ),
        ),
      );
    });

    test('creates a server with the name the account typed', () async {
      final transport = _Transport([
        _json({'id': '444444444444444444', 'name': 'Workshop'}),
        _json({
          'id': '444444444444444444',
          'name': 'Workshop',
          'owner_id': '987654321098765432',
        }),
        _json([
          {'id': '500000000000000001', 'type': 0, 'name': 'general'},
        ]),
        _json([
          {'id': '444444444444444444', 'name': '@everyone', 'position': 0},
        ]),
        const DiscordHttpResponse(
          statusCode: 404,
          headers: {},
          body: '{"message": "Not found"}',
        ),
      ]);
      final created = await _repository(
        transport,
      ).createGuild(name: 'Workshop');

      expect(created.space.name, 'Workshop');
      expect(created.channels.single.name, 'general');
      expect(transport.requests.first.method, 'POST');
      expect(transport.requests.first.uri.path, endsWith('/guilds'));
      expect(transport.requests.first.json, {'name': 'Workshop'});
    });

    test('leaves through the account route', () async {
      final transport = _Transport([
        const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
      ]);
      await _FakeSinkingRepository(transport).leaveGuild('444444444444444444');

      expect(transport.requests.single.method, 'DELETE');
      expect(
        transport.requests.single.uri.path,
        endsWith('/users/@me/guilds/444444444444444444'),
      );
    });

    test('a refused leave reports its message', () async {
      final transport = _Transport([
        const DiscordHttpResponse(
          statusCode: 400,
          headers: {},
          body: '{"message": "Cannot leave a guild you own"}',
        ),
      ]);
      expect(
        () => _repository(transport).leaveGuild('444444444444444444'),
        throwsA(
          isA<GuildAccessException>()
              .having(
                (error) => error.refusal,
                'refusal',
                GuildAccessRefusal.unknown,
              )
              .having(
                (error) => error.message,
                'message',
                contains('Cannot leave a guild you own'),
              ),
        ),
      );
    });

    test(
      'a gained guild is announced to the transport, a left one too',
      () async {
        final gainedTransport = _Transport([
          _json({'id': '444444444444444444', 'name': 'Aurora Labs'}),
          _json({
            'id': '444444444444444444',
            'name': 'Aurora Labs',
            'owner_id': '987654321098765432',
          }),
          _json([
            {'id': '500000000000000001', 'type': 0, 'name': 'general'},
          ]),
          _json([
            {'id': '444444444444444444', 'name': '@everyone', 'position': 0},
          ]),
          const DiscordHttpResponse(statusCode: 404, headers: {}, body: ''),
          const DiscordHttpResponse(statusCode: 204, headers: {}, body: ''),
        ]);
        final repository = _FakeSinkingRepository(gainedTransport);

        await repository.joinGuild('aurora');
        expect(repository.gainedIds, ['444444444444444444']);

        await repository.leaveGuild('444444444444444444');
        expect(repository.leftIds, ['444444444444444444']);
      },
    );
  });
}

/// The repository with the transport-facing sinks installed, so the announce
/// behaviour the desktop session relies on is exercised over the same wire.
final class _FakeSinkingRepository {
  _FakeSinkingRepository(_Transport transport)
    : _inner = DiscordGuildManagementRepository(_client(transport)) {
    _inner.onGuildGained = (guild) => gainedIds.add(guild.space.id);
    _inner.onGuildLeft = (guildId) => leftIds.add(guildId);
  }

  final DiscordGuildManagementRepository _inner;
  final List<String> gainedIds = [];
  final List<String> leftIds = [];

  Future<JoinedGuild> joinGuild(String code) => _inner.joinGuild(code);

  Future<void> leaveGuild(String guildId) => _inner.leaveGuild(guildId);
}
