import 'dart:convert';

import 'package:flucord/src/application/app_authorisation_controller.dart';
import 'package:flucord/src/data/discord/discord_app_authorisation_repository.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/app_authorisation.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flutter_test/flutter_test.dart';

const _guild = 'guild-1';
const _otherGuild = 'guild-2';
const _me = 'member-1';

final _inviteUrl = Uri.https('discord.com', '/oauth2/authorize', {
  'client_id': '978270835341422',
  'scope': 'bot applications.commands',
  'permissions': '8',
});

void main() {
  group('parsing an invite link', () {
    test('reads the app, its scopes, and its permissions', () {
      final invite = _repository().parseInvite(_inviteUrl);

      expect(invite, isNotNull);
      expect(invite!.applicationId, '978270835341422');
      expect(invite.scopes, ['bot', 'applications.commands']);
      expect(invite.permissions, DiscordPermissions.administrator);
      expect(invite.addsBot, isTrue);
      expect(invite.addsCommands, isTrue);
    });

    test('a guild the link names is preselected', () {
      final invite = _repository().parseInvite(
        _inviteUrl.replace(
          queryParameters: {
            ..._inviteUrl.queryParameters,
            'guild_id': '123456789',
          },
        ),
      );

      expect(invite!.guildId, '123456789');
    });

    test('scopes split on either separator Discord writes', () {
      expect(AppInvite.parseScopes('bot+applications.commands'), [
        'bot',
        'applications.commands',
      ]);
      expect(AppInvite.parseScopes(' bot '), ['bot']);
      expect(AppInvite.parseScopes(null), isEmpty);
      expect(AppInvite.parseScopes(''), isEmpty);
    });

    test('a link that is not an app invite is not one', () {
      final repository = _repository();
      expect(repository.parseInvite(Uri.https('discord.gg', '/abc')), isNull);
      expect(
        repository.parseInvite(Uri.https('example.com', '/oauth2/authorize')),
        isNull,
      );
      expect(
        repository.parseInvite(Uri.https('discord.com', '/oauth2/authorize')),
        isNull,
      );
      expect(
        repository.parseInvite(
          Uri.https('discord.com', '/oauth2/authorize', {'client_id': 'x'}),
        ),
        isNull,
      );
    });
  });

  group('the routes', () {
    test('the application record comes from the public route', () async {
      final transport = _Transport([
        _response({
          'id': '978270835341422',
          'name': 'Helper Bot',
          'description': 'Helps with things.',
          'icon': 'a hash',
          'bot': {'id': '999', 'username': 'helper'},
          'integration_public': true,
        }),
      ]);

      final application = await _repository(
        transport,
      ).loadApplication('978270835341422');

      expect(application.name, 'Helper Bot');
      expect(application.description, 'Helps with things.');
      expect(application.botUsername, 'helper');
      expect(application.isPublic, isTrue);
      expect(application.iconUrl, isNotNull);
      expect(
        transport.requests.single.uri.path,
        endsWith('/applications/978270835341422/public'),
      );
    });

    test('a private app says so', () async {
      final transport = _Transport([
        _response({
          'id': '978270835341422',
          'name': 'Private Bot',
          'bot_public': false,
        }),
      ]);

      final application = await _repository(
        transport,
      ).loadApplication('978270835341422');

      expect(application.isPublic, isFalse);
    });

    test('an app with no name falls back to its bot', () async {
      final transport = _Transport([
        _response({
          'id': '978270835341422',
          'name': '',
          'bot': {'id': '999', 'username': 'helper'},
        }),
      ]);

      final application = await _repository(
        transport,
      ).loadApplication('978270835341422');

      expect(application.name, 'helper');
    });

    test(
      'consent names the app, the server, the scopes and the permissions',
      () async {
        final transport = _Transport([
          _response({'redirect_to': 'https://x'}),
        ]);
        final invite = _repository().parseInvite(_inviteUrl)!;

        await _repository(transport).consent(invite: invite, guildId: _guild);

        expect(transport.requests.single.method, 'POST');
        expect(
          transport.requests.single.uri.path,
          endsWith('/oauth2/authorize/consent'),
        );
        expect(transport.requests.single.body, {
          'client_id': '978270835341422',
          'guild_id': _guild,
          'permissions': '8',
          'scope': 'bot applications.commands',
        });
      },
    );

    test('a guild-cap refusal names a plain refusal', () async {
      final transport = _Transport([_error(403, code: 30001)]);
      final invite = _repository().parseInvite(_inviteUrl)!;

      await expectLater(
        _repository(transport).consent(invite: invite, guildId: _guild),
        throwsA(
          isA<AppAuthorisationException>().having(
            (error) => error.failure,
            'failure',
            AppAuthorisationFailure.refused,
          ),
        ),
      );
    });

    test('a refused add is a plain refusal, not an outage', () async {
      for (final status in [400, 403]) {
        final transport = _Transport([_error(status)]);
        final invite = _repository().parseInvite(_inviteUrl)!;

        await expectLater(
          _repository(transport).consent(invite: invite, guildId: _guild),
          throwsA(
            isA<AppAuthorisationException>().having(
              (error) => error.failure,
              'failure',
              AppAuthorisationFailure.refused,
            ),
          ),
          reason: '$status',
        );
      }
    });

    test('anything else reads as declined', () async {
      final transport = _Transport([_error(500)]);
      final invite = _repository().parseInvite(_inviteUrl)!;

      await expectLater(
        _repository(transport).consent(invite: invite, guildId: _guild),
        throwsA(
          isA<AppAuthorisationException>().having(
            (error) => error.failure,
            'failure',
            AppAuthorisationFailure.denied,
          ),
        ),
      );
    });

    test('the grants come from the authorizations route', () async {
      final transport = _Transport([
        _response([
          {
            'application': {
              'id': '978270835341422',
              'name': 'Helper Bot',
              'description': 'Helps with things.',
              'icon': 'a hash',
            },
            'scopes': ['bot', 'applications.commands'],
            'authorized_at': '2026-09-01T10:00:00+00:00',
          },
          // A row whose application carries no id names nothing and can be
          // revoked by nothing.
          {
            'application': {'name': 'Nameless'},
            'scopes': ['bot'],
          },
        ]),
      ]);

      final grants = await _repository(transport).loadAuthorisedApplications();

      expect(grants.single.applicationId, '978270835341422');
      expect(grants.single.name, 'Helper Bot');
      expect(grants.single.description, 'Helps with things.');
      expect(grants.single.scopes, ['bot', 'applications.commands']);
      expect(grants.single.authorizedAt, isNotNull);
      expect(grants.single.iconUrl, isNotNull);
      expect(
        transport.requests.single.uri.path,
        endsWith('/oauth2/@me/authorizations'),
      );
    });

    test('revoking names the application id', () async {
      final transport = _Transport([_response(const <String, Object?>{})]);
      const grant = AuthorisedApplication(
        applicationId: '978270835341422',
        name: 'Helper Bot',
      );

      await _repository(transport).revokeAuthorisedApplication(grant);

      expect(transport.requests.single.method, 'DELETE');
      expect(
        transport.requests.single.uri.path,
        endsWith('/oauth2/@me/authorizations/978270835341422'),
      );
    });

    test('a revoke Discord would not take is a plain refusal', () async {
      for (final status in [400, 403, 404]) {
        final transport = _Transport([_error(status)]);
        const grant = AuthorisedApplication(
          applicationId: '978270835341422',
          name: 'Helper Bot',
        );

        await expectLater(
          _repository(transport).revokeAuthorisedApplication(grant),
          throwsA(
            isA<AppAuthorisationException>().having(
              (error) => error.failure,
              'failure',
              AppAuthorisationFailure.refused,
            ),
          ),
          reason: '$status',
        );
      }
    });

    test('anything else on the grants routes is still an error', () async {
      final transport = _Transport([_error(500)]);
      const grant = AuthorisedApplication(
        applicationId: '978270835341422',
        name: 'Helper Bot',
      );

      await expectLater(
        _repository(transport).revokeAuthorisedApplication(grant),
        throwsA(isA<DiscordApiException>()),
      );
    });
  });

  group('the controller', () {
    test(
      'reads an invite, states what it asks, and offers the servers',
      () async {
        final repository = _FakeAuthorisation();
        final controller = AppAuthorisationController(
          () => repository,
          () => _workspace(manageGuild: true),
        );
        addTearDown(controller.dispose);

        expect(await controller.readInvite(_inviteUrl.toString()), isTrue);

        expect(controller.stage, AppAuthorisationStage.awaitingConsent);
        expect(controller.application!.name, 'Helper Bot');
        expect(controller.requestedPermissionLabels, contains('Administrator'));
        expect(controller.guilds, hasLength(2));
        // The first server is picked, so the consent button can be used at once.
        expect(controller.selectedGuildId, controller.guilds.first.id);
      },
    );

    test('consent adds the app to the chosen server', () async {
      final repository = _FakeAuthorisation();
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);

      await controller.readInvite(_inviteUrl.toString());
      controller.selectGuild(_otherGuild);
      expect(await controller.consent(), isTrue);

      expect(controller.stage, AppAuthorisationStage.added);
      expect(repository.consentedGuild, _otherGuild);
    });

    test('a transport that cannot consent does nothing', () async {
      final controller = AppAuthorisationController(
        () => null,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);

      expect(controller.isAvailable, isFalse);
      expect(await controller.readInvite(_inviteUrl.toString()), isFalse);
      expect(await controller.consent(), isFalse);
      expect(controller.error, isNull);
    });

    test('a link that is not an app invite clears the page', () async {
      final repository = _FakeAuthorisation();
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);

      await controller.readInvite(_inviteUrl.toString());
      expect(await controller.readInvite('https://discord.gg/abc'), isFalse);

      expect(controller.invite, isNull);
      expect(controller.stage, AppAuthorisationStage.idle);
    });

    test('only servers the account manages are offered', () async {
      final repository = _FakeAuthorisation();
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: false),
      );
      addTearDown(controller.dispose);

      await controller.readInvite(_inviteUrl.toString());

      expect(controller.guilds, isEmpty);
      expect(controller.selectedGuildId, isNull);
      expect(await controller.consent(), isFalse);
    });

    test('a guild the link names is preselected', () async {
      final repository = _FakeAuthorisation();
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);

      final url = _inviteUrl.replace(
        queryParameters: {
          ..._inviteUrl.queryParameters,
          'guild_id': _otherGuild,
        },
      );
      await controller.readInvite(url.toString());

      // The link's choice stands even when it names a server this client
      // knows by another id: consent is about the link's target, not about
      // the rail's order.
      expect(controller.selectedGuildId, _otherGuild);
    });

    test('an app that cannot be read is an error', () async {
      final repository = _FakeAuthorisation()..failNextApplication = true;
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);

      await controller.readInvite(_inviteUrl.toString());

      expect(controller.error, isA<StateError>());
      expect(controller.stage, AppAuthorisationStage.readingInvite);
    });

    test(
      'a failed read leaves the error reachable and retry recovers',
      () async {
        final repository = _FakeAuthorisation()..failNextApplication = true;
        final controller = AppAuthorisationController(
          () => repository,
          () => _workspace(manageGuild: true),
        );
        addTearDown(controller.dispose);

        expect(await controller.readInvite(_inviteUrl.toString()), isFalse);
        // The stage is where the read stopped and the error stands beside it,
        // which is what the page's retry reads.
        expect(controller.error, isA<StateError>());
        expect(controller.stage, AppAuthorisationStage.readingInvite);
        expect(controller.invite, isNotNull);

        repository.failNextApplication = false;
        expect(await controller.readInvite(_inviteUrl.toString()), isTrue);
        expect(controller.error, isNull);
        expect(controller.stage, AppAuthorisationStage.awaitingConsent);
      },
    );

    test('a refusal names which one it was', () async {
      final repository = _FakeAuthorisation()
        ..refuseWith = AppAuthorisationFailure.refused;
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);

      await controller.readInvite(_inviteUrl.toString());
      expect(await controller.consent(), isFalse);

      expect(controller.refusal!.failure, AppAuthorisationFailure.refused);
      expect(controller.error, isNull);
      expect(controller.stage, AppAuthorisationStage.awaitingConsent);
    });

    test('reset drops the invite and the choice', () async {
      final repository = _FakeAuthorisation();
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);

      await controller.readInvite(_inviteUrl.toString());
      controller.reset();

      expect(controller.invite, isNull);
      expect(controller.guilds, isEmpty);
      expect(controller.selectedGuildId, isNull);
      expect(controller.stage, AppAuthorisationStage.idle);
    });

    test('a bot invite with no permissions says so', () async {
      final repository = _FakeAuthorisation();
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);

      final url = Uri.https('discord.com', '/oauth2/authorize', {
        'client_id': '978270835341422',
        'scope': 'bot',
      });
      await controller.readInvite(url.toString());

      expect(controller.requestedPermissionLabels, ['No extra permissions']);
    });

    test('disposing stops notifications', () async {
      final controller = AppAuthorisationController(
        _FakeAuthorisation.new,
        () => _workspace(manageGuild: true),
      );
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..dispose();

      await controller.readInvite(_inviteUrl.toString());

      expect(notifications, 0);
    });

    test('lists the grants this account has made', () async {
      final repository = _FakeAuthorisation()
        ..grants = const [
          AuthorisedApplication(
            applicationId: '978270835341422',
            name: 'Helper Bot',
            description: 'Helps with things.',
            scopes: ['bot'],
          ),
        ];
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);

      await controller.loadAuthorisedApplications();

      expect(controller.grants.single.name, 'Helper Bot');
      expect(controller.revokeRefusal, isNull);
    });

    test('the grants are loaded once, and again only when asked', () async {
      final repository = _FakeAuthorisation();
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);

      await controller.loadAuthorisedApplications();
      expect(controller.grants, isEmpty);

      repository.grants = const [
        AuthorisedApplication(applicationId: '1', name: 'One'),
      ];
      await controller.loadAuthorisedApplications();
      // Cached: the list is only re-read when asked for.
      expect(controller.grants, isEmpty);

      await controller.loadAuthorisedApplications(refresh: true);
      expect(controller.grants.single.name, 'One');
    });

    test('a failed read can be retried', () async {
      final repository = _FakeAuthorisation()..failNextGrants = true;
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);

      await controller.loadAuthorisedApplications();
      expect(controller.error, isA<StateError>());
      expect(controller.grants, isEmpty);

      await controller.loadAuthorisedApplications(refresh: true);
      expect(controller.error, isNull);
      expect(controller.grants, isEmpty);
    });

    test('revoking takes the grant away', () async {
      final grant = const AuthorisedApplication(
        applicationId: '978270835341422',
        name: 'Helper Bot',
      );
      final repository = _FakeAuthorisation()..grants = [grant];
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);
      await controller.loadAuthorisedApplications();

      expect(await controller.revokeAuthorisedApplication(grant), isTrue);

      expect(controller.grants, isEmpty);
      expect(repository.grants, isEmpty);
      expect(controller.revokeRefusal, isNull);
    });

    test('a revoke Discord refused is named, not read as an outage', () async {
      final grant = const AuthorisedApplication(
        applicationId: '978270835341422',
        name: 'Helper Bot',
      );
      final repository = _FakeAuthorisation()
        ..grants = [grant]
        ..refuseRevoke = true;
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);
      await controller.loadAuthorisedApplications();

      expect(await controller.revokeAuthorisedApplication(grant), isFalse);

      expect(controller.revokeRefusal, 'Helper Bot');
      expect(controller.error, isNull);
      expect(controller.grants, isNotEmpty);
    });

    test('a revoke that could not be sent is an error', () async {
      final grant = const AuthorisedApplication(
        applicationId: '978270835341422',
        name: 'Helper Bot',
      );
      final repository = _FakeAuthorisation()
        ..grants = [grant]
        ..failNextRevoke = true;
      final controller = AppAuthorisationController(
        () => repository,
        () => _workspace(manageGuild: true),
      );
      addTearDown(controller.dispose);
      await controller.loadAuthorisedApplications();

      expect(await controller.revokeAuthorisedApplication(grant), isFalse);

      expect(controller.error, isA<StateError>());
      expect(controller.revokeRefusal, isNull);
    });
  });
}

DiscordAppAuthorisationRepository _repository([_Transport? transport]) =>
    DiscordAppAuthorisationRepository(
      DiscordRestClient(
        authorization: DiscordDesktopAuthorization('token'),
        transport: transport,
        baseUri: Uri.parse('https://discord.com/api/v9'),
      ),
    );

/// Two guilds, one of which this account manages.
ChatWorkspace _workspace({required bool manageGuild}) => ChatWorkspace(
  spaces: [
    CommunitySpace(
      id: _guild,
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
    ),
    CommunitySpace(
      id: _otherGuild,
      name: 'The Library',
      monogram: 'TL',
      colorValue: 0xff456b5a,
    ),
  ],
  channels: [
    ConversationChannel(
      id: 'general',
      spaceId: _guild,
      name: 'general',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  roles: [
    CommunityRole(
      id: _guild,
      spaceId: _guild,
      name: '@everyone',
      position: 0,
      permissions: manageGuild
          ? DiscordPermissions.manageGuild
          : DiscordPermissions.none,
    ),
    CommunityRole(
      id: _otherGuild,
      spaceId: _otherGuild,
      name: '@everyone',
      position: 0,
      permissions: manageGuild
          ? DiscordPermissions.manageGuild
          : DiscordPermissions.none,
    ),
  ],
  members: [
    Member(
      id: _me,
      displayName: 'Ada',
      initials: 'A',
      role: 'Member',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: const {_guild, _otherGuild},
      membershipsBySpace: const {
        _guild: GuildMembership(),
        _otherGuild: GuildMembership(),
      },
    ),
  ],
  messages: const [],
  currentMemberId: _me,
);

final class _FakeAuthorisation implements AppAuthorisationRepository {
  String? consentedGuild;
  bool failNextApplication = false;
  AppAuthorisationFailure? refuseWith;

  List<AuthorisedApplication> grants = const [];
  bool failNextGrants = false;
  bool refuseRevoke = false;
  bool failNextRevoke = false;

  @override
  Future<List<AuthorisedApplication>> loadAuthorisedApplications() async {
    if (failNextGrants) {
      failNextGrants = false;
      throw StateError('grants failed');
    }
    return grants;
  }

  @override
  Future<void> revokeAuthorisedApplication(
    AuthorisedApplication application,
  ) async {
    if (failNextRevoke) {
      failNextRevoke = false;
      throw StateError('revoke failed');
    }
    if (refuseRevoke) {
      throw const AppAuthorisationException(AppAuthorisationFailure.refused);
    }
    grants = [
      for (final other in grants)
        if (other != application) other,
    ];
  }

  static const _app = AppInviteApplication(
    id: '978270835341422',
    name: 'Helper Bot',
    description: 'Helps with things.',
    isPublic: true,
  );

  @override
  AppInvite? parseInvite(Uri uri) {
    if (uri.host != 'discord.com' || uri.path != '/oauth2/authorize') {
      return null;
    }
    final clientId = uri.queryParameters['client_id'];
    final scopes = AppInvite.parseScopes(uri.queryParameters['scope']);
    if (clientId == null || clientId.isEmpty || scopes.isEmpty) return null;
    return AppInvite(
      applicationId: clientId,
      scopes: scopes,
      permissions: DiscordPermissions.tryParse(
        uri.queryParameters['permissions'],
      ),
      guildId: uri.queryParameters['guild_id'],
    );
  }

  @override
  Future<AppInviteApplication> loadApplication(String applicationId) async {
    if (failNextApplication) {
      failNextApplication = false;
      throw StateError('application failed');
    }
    return _app;
  }

  @override
  Future<void> consent({
    required AppInvite invite,
    required String guildId,
  }) async {
    if (refuseWith case final failure?) {
      throw AppAuthorisationException(failure);
    }
    consentedGuild = guildId;
  }
}

DiscordHttpResponse _response(Object payload) => DiscordHttpResponse(
  statusCode: 200,
  headers: const {},
  body: jsonEncode(payload),
);

DiscordHttpResponse _error(int status, {int? code}) => DiscordHttpResponse(
  statusCode: status,
  headers: const {},
  body: jsonEncode({'message': 'Refused', 'code': ?code}),
);

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
        method,
        uri,
        body == null
            ? null
            : jsonDecode(utf8.decode(body)) as Map<String, Object?>,
      ),
    );
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}

final class _Recorded {
  const _Recorded(this.method, this.uri, this.body);

  final String method;
  final Uri uri;
  final Map<String, Object?>? body;
}
