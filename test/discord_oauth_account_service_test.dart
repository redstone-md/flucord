import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_oauth_account_service.dart';
import 'package:flucord/src/data/discord/discord_oauth_identity_client.dart';
import 'package:flucord/src/data/discord/discord_oauth_token_client.dart';
import 'package:flucord/src/data/discord/discord_rest_client.dart';
import 'package:flucord/src/domain/discord_oauth.dart';
import 'package:flucord/src/domain/discord_session.dart';
import 'package:flucord/src/domain/external_link_launcher.dart';

void main() {
  test('completes a state-bound S256 public-client authorization', () async {
    final tokenTransport = _RecordingTransport(const [
      DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body:
            '{"token_type":"Bearer","access_token":"access-1",'
            '"refresh_token":"refresh-1","expires_in":3600,'
            '"scope":"identify guilds guilds.members.read connections"}',
      ),
    ]);
    final identityTransport = _RecordingTransport(const [
      DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body:
            '{"id":"123456789012345678","username":"jack",'
            '"global_name":"Jack","discriminator":"0",'
            '"avatar":"avatar-hash","banner":"banner-hash",'
            '"accent_color":5793266,"locale":"en-US",'
            '"verified":true,"mfa_enabled":true,"public_flags":64}',
      ),
      DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body:
            '[{"id":"guild-1","name":"The Forge","owner":true,'
            '"permissions":"8","approximate_member_count":42,'
            '"approximate_presence_count":7},{"id":"guild-2",'
            '"name":"Night Shift","permissions":"0"}]',
      ),
      DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body:
            '[{"id":"spotify-1","name":"jack.fm","type":"spotify",'
            '"verified":true,"friend_sync":false,"show_activity":true,'
            '"two_way_link":true,"visibility":1}]',
      ),
    ]);
    final launcher = _RecordingLauncher();
    final vault = _MemoryGrantVault();
    final service = _service(
      launcher: launcher,
      vault: vault,
      tokenTransport: tokenTransport,
      identityTransport: identityTransport,
    );
    addTearDown(service.dispose);

    final authorization = service.authorize();
    final authorizeUri = await launcher.opened.future;
    expect(authorizeUri.host, 'discord.com');
    expect(authorizeUri.path, '/oauth2/authorize');
    expect(authorizeUri.queryParameters['response_type'], 'code');
    expect(
      authorizeUri.queryParameters['scope'],
      'identify guilds guilds.members.read connections',
    );
    expect(authorizeUri.queryParameters['code_challenge_method'], 'S256');
    final state = authorizeUri.queryParameters['state']!;

    expect(
      await service.handleRedirect(
        Uri.parse('flucord://oauth/discord/callback?code=code-1&state=$state'),
      ),
      isTrue,
    );
    final account = await authorization;

    expect(account.displayName, 'Jack');
    expect(account.usernameLabel, '@jack');
    expect(account.bannerUrl, contains('/banners/123456789012345678/'));
    expect(account.accentColor, 5793266);
    expect(account.locale, 'en-US');
    expect(account.isVerified, isTrue);
    expect(account.mfaEnabled, isTrue);
    expect(account.publicFlags, 64);
    expect(account.guildCount, 2);
    expect(account.guilds.first.name, 'The Forge');
    expect(account.guilds.first.isOwner, isTrue);
    expect(account.guilds.first.approximateMemberCount, 42);
    expect(account.connections.single.name, 'jack.fm');
    expect(account.connections.single.verified, isTrue);
    expect(account.avatarUrl, contains('/avatars/123456789012345678/'));
    expect(vault.grant?.refreshToken, 'refresh-1');
    final form = Uri.splitQueryString(
      utf8.decode(tokenTransport.requests.single.body),
    );
    final verifier = form['code_verifier']!;
    expect(
      authorizeUri.queryParameters['code_challenge'],
      await _challenge(verifier),
    );
    expect(form, isNot(contains('client_secret')));
    expect(
      identityTransport.requests.first.headers['authorization'],
      'Bearer access-1',
    );
  });

  test('rejects a callback with a mismatched state before exchange', () async {
    final launcher = _RecordingLauncher();
    final tokenTransport = _RecordingTransport(const []);
    final service = _service(
      launcher: launcher,
      vault: _MemoryGrantVault(),
      tokenTransport: tokenTransport,
      identityTransport: _RecordingTransport(const []),
    );
    addTearDown(service.dispose);

    final authorization = service.authorize();
    await launcher.opened.future;
    final rejection = expectLater(
      authorization,
      throwsA(
        isA<DiscordOAuthException>().having(
          (error) => error.message,
          'message',
          contains('invalid state'),
        ),
      ),
    );
    await service.handleRedirect(
      Uri.parse(
        'flucord://oauth/discord/callback?code=code-1&state=wrong-state',
      ),
    );

    await rejection;
    expect(tokenTransport.requests, isEmpty);
  });

  test('refreshes and persists a rotated grant before restore', () async {
    final now = DateTime.utc(2099, 7, 24, 4);
    final vault = _MemoryGrantVault()
      ..grant = DiscordOAuthGrant(
        accessToken: 'expired-access',
        refreshToken: 'refresh-1',
        scopes: const {
          'identify',
          'guilds',
          'guilds.members.read',
          'connections',
        },
        expiresAt: now,
      );
    final tokenTransport = _RecordingTransport(const [
      DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body:
            '{"token_type":"Bearer","access_token":"access-2",'
            '"refresh_token":"refresh-2","expires_in":3600,'
            '"scope":"identify guilds guilds.members.read connections"}',
      ),
    ]);
    final identityTransport = _RecordingTransport(const [
      DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body: '{"id":"123456789012345678","username":"jack"}',
      ),
      DiscordHttpResponse(statusCode: 200, headers: {}, body: '[]'),
      DiscordHttpResponse(statusCode: 200, headers: {}, body: '[]'),
    ]);
    final service = _service(
      launcher: _RecordingLauncher(),
      vault: vault,
      tokenTransport: tokenTransport,
      identityTransport: identityTransport,
      clock: () => now,
    );
    addTearDown(service.dispose);

    final account = await service.restore();

    expect(account?.username, 'jack');
    expect(vault.grant?.accessToken, 'access-2');
    expect(vault.grant?.refreshToken, 'refresh-2');
    final form = Uri.splitQueryString(
      utf8.decode(tokenTransport.requests.single.body),
    );
    expect(form['grant_type'], 'refresh_token');
    expect(form['refresh_token'], 'refresh-1');
  });

  test('loads documented current-user guild membership on demand', () async {
    final vault = _MemoryGrantVault()
      ..grant = DiscordOAuthGrant(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        scopes: const {'identify', 'guilds', 'guilds.members.read'},
        expiresAt: DateTime.utc(2100),
      );
    final identityTransport = _RecordingTransport(const [
      DiscordHttpResponse(
        statusCode: 200,
        headers: {},
        body:
            '{"user":{"id":"123456789012345678"},'
            '"nick":"Fly","avatar":"member-hash",'
            '"roles":["role-1","role-2"],'
            '"joined_at":"2024-01-02T03:04:05Z",'
            '"premium_since":"2025-02-03T04:05:06Z",'
            '"pending":true,'
            '"communication_disabled_until":"2026-03-04T05:06:07Z"}',
      ),
    ]);
    final service = _service(
      launcher: _RecordingLauncher(),
      vault: vault,
      tokenTransport: _RecordingTransport(const []),
      identityTransport: identityTransport,
    );
    addTearDown(service.dispose);

    final membership = await service.fetchCurrentGuildMembership(
      '987654321098765432',
    );

    expect(membership.nickname, 'Fly');
    expect(membership.roleIds, const ['role-1', 'role-2']);
    expect(membership.joinedAt, DateTime.utc(2024, 1, 2, 3, 4, 5));
    expect(membership.premiumSince, isNotNull);
    expect(membership.pending, isTrue);
    expect(membership.communicationDisabledUntil, isNotNull);
    expect(
      membership.avatarUrl,
      contains('/guilds/987654321098765432/users/123456789012345678/'),
    );
    final request = identityTransport.requests.single;
    expect(request.method, 'GET');
    expect(
      request.uri.path,
      '/api/v10/users/@me/guilds/987654321098765432/member',
    );
    expect(request.headers['authorization'], 'Bearer access-1');
  });

  test(
    'requires relinking a saved grant that lacks membership scope',
    () async {
      final vault = _MemoryGrantVault()
        ..grant = DiscordOAuthGrant(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          scopes: const {'identify', 'guilds'},
          expiresAt: DateTime.utc(2100),
        );
      final identityTransport = _RecordingTransport(const []);
      final service = _service(
        launcher: _RecordingLauncher(),
        vault: vault,
        tokenTransport: _RecordingTransport(const []),
        identityTransport: identityTransport,
      );
      addTearDown(service.dispose);

      await expectLater(
        service.fetchCurrentGuildMembership('987654321098765432'),
        throwsA(
          isA<DiscordOAuthException>().having(
            (error) => error.message,
            'message',
            contains('Relink Discord'),
          ),
        ),
      );
      expect(identityTransport.requests, isEmpty);
    },
  );

  test('ignores unrelated protocol URLs', () async {
    final service = _service(
      launcher: _RecordingLauncher(),
      vault: _MemoryGrantVault(),
      tokenTransport: _RecordingTransport(const []),
      identityTransport: _RecordingTransport(const []),
    );
    addTearDown(service.dispose);

    expect(
      await service.handleRedirect(
        Uri.parse('flucord://channels/guild/channel'),
      ),
      isFalse,
    );
  });
}

NativeDiscordOAuthAccountService _service({
  required _RecordingLauncher launcher,
  required _MemoryGrantVault vault,
  required _RecordingTransport tokenTransport,
  required _RecordingTransport identityTransport,
  DateTime Function()? clock,
}) => NativeDiscordOAuthAccountService(
  configuration: DiscordOAuthConfiguration(
    clientId: 'application-1',
    redirectUri: Uri.parse('flucord://oauth/discord/callback'),
  ),
  launcher: launcher,
  vault: vault,
  tokenClient: DiscordOAuthTokenClient(
    transport: tokenTransport,
    clock: clock ?? () => DateTime.utc(2099, 7, 24, 4),
  ),
  identityFactory: (DiscordOAuthUserSession session) =>
      DiscordOAuthIdentityClient(
        session: session,
        transport: identityTransport,
      ),
  entropySource: (length) =>
      List.generate(length, (index) => index % 256, growable: false),
  clock: clock ?? () => DateTime.utc(2099, 7, 24, 4),
);

Future<String> _challenge(String verifier) async {
  final sink = Sha256().newHashSink();
  sink.add(utf8.encode(verifier));
  sink.close();
  final hash = await sink.hash();
  return base64UrlEncode(hash.bytes).replaceAll('=', '');
}

final class _RecordingLauncher implements ExternalLinkLauncher {
  final Completer<Uri> opened = Completer<Uri>();

  @override
  Future<bool> open(Uri uri) async {
    opened.complete(uri);
    return true;
  }
}

final class _MemoryGrantVault implements DiscordOAuthGrantVault {
  DiscordOAuthGrant? grant;

  @override
  Future<void> clear() async => grant = null;

  @override
  Future<DiscordOAuthGrant?> read() async => grant;

  @override
  Future<void> write(DiscordOAuthGrant grant) async => this.grant = grant;
}

final class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;
}

final class _RecordingTransport implements DiscordHttpTransport {
  _RecordingTransport(List<DiscordHttpResponse> responses)
    : _responses = [...responses];

  final List<DiscordHttpResponse> _responses;
  final List<_RecordedRequest> requests = [];

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    requests.add(
      _RecordedRequest(
        method: method,
        uri: uri,
        headers: Map.unmodifiable(headers),
        body: List.unmodifiable(body ?? const []),
      ),
    );
    return _responses.removeAt(0);
  }

  @override
  void close() {}
}
