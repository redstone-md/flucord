part of 'guild_management_repository_test.dart';

/// The account's own server profile: `GET` and `PATCH
/// /guilds/{id}/members/@me`.
void _ownServerProfileCases() {
  group('own server profile', () {
    test('reads the nickname, avatar, banner and bio of one server', () async {
      final transport = _Transport([
        _json({
          'user': {'id': '123456789012345678', 'username': 'mira'},
          'nick': 'Forge Mira',
          'avatar': 'a1b2',
          'banner': 'c3d4',
          'bio': 'Smith by trade.',
          'roles': <Object?>[],
        }),
      ]);
      final profile = await _repository(
        transport,
      ).loadOwnServerProfile('111111111111111111');

      expect(transport.requests.single.method, 'GET');
      expect(
        transport.requests.single.uri.path,
        endsWith('/guilds/111111111111111111/members/@me'),
      );
      expect(profile.nickname, 'Forge Mira');
      expect(profile.avatarHash, 'a1b2');
      expect(profile.bannerHash, 'c3d4');
      expect(profile.bio, 'Smith by trade.');
    });

    test('sends only the fields the edit touched', () async {
      final transport = _Transport([
        _json({
          'user': {'id': '123456789012345678', 'username': 'mira'},
          'nick': 'Smith',
          'avatar': 'fresh',
          'bio': '',
        }),
      ]);
      final saved = await _repository(transport).saveOwnServerProfile(
        guildId: '111111111111111111',
        edit: const ServerProfileEdit(
          nickname: ProfileValue.set('Smith'),
          avatar: ProfileImage.replaced('data:image/png;base64,AAAA'),
          banner: ProfileImage.removed(),
        ),
      );

      final request = transport.requests.single;
      expect(request.method, 'PATCH');
      expect(
        request.uri.path,
        endsWith('/guilds/111111111111111111/members/@me'),
      );
      // The bio was left alone, so it is not in the body at all. The banner
      // was removed, which is an explicit null.
      expect(request.json, {
        'nick': 'Smith',
        'avatar': 'data:image/png;base64,AAAA',
        'banner': null,
      });
      expect(saved.nickname, 'Smith');
      expect(saved.avatarHash, 'fresh');
      expect(saved.bannerHash, isNull);
      expect(saved.bio, isEmpty);
    });

    test('a cleared nickname is sent as null', () {
      const edit = ServerProfileEdit(
        nickname: ProfileValue.cleared(),
        bio: ProfileValue.set('Hello'),
      );
      expect(edit.toJson(), {'nick': null, 'bio': 'Hello'});
      expect(const ServerProfileEdit().isEmpty, isTrue);
    });

    test('a refusal names what Discord refused, in its words', () async {
      final transport = _Transport([
        DiscordHttpResponse(
          statusCode: 400,
          headers: const {},
          body: jsonEncode({
            'code': 50035,
            'message': 'Invalid Form Body',
            'errors': {
              'nick': {
                '_errors': [
                  {
                    'code': 'BASE_TYPE_BAD_LENGTH',
                    'message': 'Must be between 1 and 32 in length.',
                  },
                ],
              },
            },
          }),
        ),
      ]);
      expect(
        () => _repository(transport).saveOwnServerProfile(
          guildId: '111111111111111111',
          edit: const ServerProfileEdit(nickname: ProfileValue.set('')),
        ),
        throwsA(
          isA<ServerProfileRefusal>().having(
            (error) => error.message,
            'message',
            'Discord did not save your server profile: Must be between 1 '
                'and 32 in length.',
          ),
        ),
      );
    });

    test('a missing permission refusal says so plainly', () async {
      final transport = _Transport([
        const DiscordHttpResponse(
          statusCode: 403,
          headers: {},
          body: '{"message": "Missing Permissions", "code": 50013}',
        ),
      ]);
      expect(
        () => _repository(transport).saveOwnServerProfile(
          guildId: '111111111111111111',
          edit: const ServerProfileEdit(nickname: ProfileValue.set('Smith')),
        ),
        throwsA(
          isA<ServerProfileRefusal>().having(
            (error) => error.message,
            'message',
            'This server does not let you change that.',
          ),
        ),
      );
    });
  });
}
