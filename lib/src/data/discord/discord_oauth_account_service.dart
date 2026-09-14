import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../domain/discord_oauth.dart';
import '../../domain/discord_session.dart';
import '../../domain/external_link_launcher.dart';
import 'discord_oauth_account_mapper.dart';
import 'discord_oauth_guild_membership_mapper.dart';
import 'discord_oauth_identity_client.dart';
import 'discord_oauth_token_client.dart';

typedef DiscordOAuthEntropySource = List<int> Function(int length);
typedef DiscordOAuthIdentityFactory =
    DiscordOAuthIdentityClient Function(DiscordOAuthUserSession session);

final class DiscordOAuthConfiguration {
  factory DiscordOAuthConfiguration({
    required String clientId,
    required Uri redirectUri,
    Iterable<String> scopes = const {
      'identify',
      'guilds',
      'guilds.members.read',
      'connections',
    },
  }) {
    final normalizedClientId = clientId.trim();
    final normalizedScopes = Set.unmodifiable(
      scopes.map((scope) => scope.trim()).where((scope) => scope.isNotEmpty),
    );
    if (normalizedClientId.isEmpty) {
      throw ArgumentError.value(clientId, 'clientId', 'Cannot be empty');
    }
    if (redirectUri.scheme != 'flucord' ||
        redirectUri.host != 'oauth' ||
        redirectUri.path != '/discord/callback' ||
        redirectUri.hasQuery ||
        redirectUri.hasFragment) {
      throw ArgumentError.value(
        redirectUri,
        'redirectUri',
        'Must equal flucord://oauth/discord/callback',
      );
    }
    if (!normalizedScopes.contains('identify')) {
      throw ArgumentError.value(scopes, 'scopes', 'identify is required');
    }
    return DiscordOAuthConfiguration._(
      normalizedClientId,
      redirectUri,
      normalizedScopes,
    );
  }

  const DiscordOAuthConfiguration._(
    this.clientId,
    this.redirectUri,
    this.scopes,
  );

  static DiscordOAuthConfiguration? fromEnvironment() {
    const clientId = String.fromEnvironment('FLUCORD_DISCORD_CLIENT_ID');
    if (clientId.trim().isEmpty) return null;
    return DiscordOAuthConfiguration(
      clientId: clientId,
      redirectUri: Uri.parse('flucord://oauth/discord/callback'),
    );
  }

  final String clientId;
  final Uri redirectUri;
  final Set<String> scopes;
}

final class NativeDiscordOAuthAccountService
    implements DiscordOAuthAccountGateway {
  factory NativeDiscordOAuthAccountService({
    required DiscordOAuthConfiguration? configuration,
    required ExternalLinkLauncher launcher,
    required DiscordOAuthGrantVault vault,
    DiscordOAuthTokenClient? tokenClient,
    DiscordOAuthIdentityFactory? identityFactory,
    DiscordOAuthEntropySource? entropySource,
    DiscordClock? clock,
    DiscordOAuthAccountMapper accountMapper = const DiscordOAuthAccountMapper(),
    DiscordOAuthGuildMembershipMapper membershipMapper =
        const DiscordOAuthGuildMembershipMapper(),
  }) => NativeDiscordOAuthAccountService._(
    configuration,
    launcher,
    vault,
    tokenClient ?? DiscordOAuthTokenClient(),
    identityFactory ??
        ((session) => DiscordOAuthIdentityClient(session: session)),
    entropySource ?? _secureBytes,
    clock ?? DateTime.now,
    accountMapper,
    membershipMapper,
  );

  NativeDiscordOAuthAccountService._(
    this._configuration,
    this._launcher,
    this._vault,
    this._tokenClient,
    this._identityFactory,
    this._entropySource,
    this._clock,
    this._accountMapper,
    this._membershipMapper,
  );

  final DiscordOAuthConfiguration? _configuration;
  final ExternalLinkLauncher _launcher;
  final DiscordOAuthGrantVault _vault;
  final DiscordOAuthTokenClient _tokenClient;
  final DiscordOAuthIdentityFactory _identityFactory;
  final DiscordOAuthEntropySource _entropySource;
  final DiscordClock _clock;
  final DiscordOAuthAccountMapper _accountMapper;
  final DiscordOAuthGuildMembershipMapper _membershipMapper;

  _PendingAuthorization? _pending;
  bool _disposed = false;

  @override
  bool get isConfigured => _configuration != null;

  @override
  Future<DiscordOAuthAccount?> restore() async {
    final configuration = _configuration;
    if (configuration == null) return null;
    final grant = await _readGrant(configuration);
    if (grant == null) return null;
    return _loadAccount(grant);
  }

  @override
  Future<DiscordOAuthGuildMembership> fetchCurrentGuildMembership(
    String guildId,
  ) async {
    _ensureActive();
    final configuration = _configuration;
    if (configuration == null) {
      throw const DiscordOAuthException(
        'Discord account linking is unavailable in this build.',
      );
    }
    final grant = await _readGrant(configuration);
    if (grant == null) {
      throw const DiscordOAuthException('No Discord account is linked.');
    }
    if (!grant.scopes.contains('guilds.members.read')) {
      throw const DiscordOAuthException(
        'Relink Discord to authorize server membership details.',
      );
    }
    final client = _identityFactory(grant.session);
    try {
      final payload = await client.getCurrentUserGuildMember(guildId);
      return _membershipMapper.map(guildId: guildId, payload: payload);
    } finally {
      client.close();
    }
  }

  @override
  Future<DiscordOAuthAccount> authorize() async {
    _ensureActive();
    final configuration = _configuration;
    if (configuration == null) {
      throw const DiscordOAuthException(
        'Discord account linking is unavailable in this build.',
      );
    }
    final existing = _pending;
    if (existing != null) return existing.completer.future;

    final verifier = _token(_entropySource(64));
    final state = _token(_entropySource(32));
    final challenge = await _codeChallenge(verifier);
    final pending = _PendingAuthorization(
      state: state,
      verifier: verifier,
      completer: Completer<DiscordOAuthAccount>(),
    );
    _pending = pending;
    final uri = Uri.https('discord.com', '/oauth2/authorize', {
      'client_id': configuration.clientId,
      'response_type': 'code',
      'redirect_uri': configuration.redirectUri.toString(),
      'scope': configuration.scopes.join(' '),
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });
    var opened = false;
    try {
      opened = await _launcher.open(uri);
    } on Object {
      opened = false;
    }
    if (!opened) {
      _failPending(
        const DiscordOAuthException(
          'The system browser could not open Discord authorization.',
        ),
      );
    }
    return pending.completer.future;
  }

  @override
  Future<bool> handleRedirect(Uri uri) async {
    final configuration = _configuration;
    if (configuration == null || !_matchesRedirect(uri, configuration)) {
      return false;
    }
    final pending = _pending;
    if (pending == null) return true;
    if (!_constantTimeEquals(uri.queryParameters['state'], pending.state)) {
      _failPending(
        const DiscordOAuthException(
          'Discord authorization returned an invalid state.',
        ),
      );
      return true;
    }
    final error = uri.queryParameters['error'];
    if (error != null) {
      _failPending(
        DiscordOAuthException(
          error == 'access_denied'
              ? 'Discord authorization was declined.'
              : 'Discord authorization failed ($error).',
        ),
      );
      return true;
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      _failPending(
        const DiscordOAuthException('Discord authorization returned no code.'),
      );
      return true;
    }
    try {
      final grant = await _tokenClient.exchangeCode(
        clientId: configuration.clientId,
        code: code,
        redirectUri: configuration.redirectUri,
        codeVerifier: pending.verifier,
      );
      if (!grant.scopes.containsAll(configuration.scopes)) {
        throw const DiscordOAuthException(
          'Discord returned fewer OAuth scopes than requested.',
        );
      }
      await _vault.write(grant);
      final account = await _loadAccount(grant);
      _completePending(account);
    } on Object catch (error, stackTrace) {
      _failPending(error, stackTrace);
    }
    return true;
  }

  Future<DiscordOAuthGrant> _refresh(
    DiscordOAuthConfiguration configuration,
    DiscordOAuthGrant grant,
  ) async {
    final refreshed = await _tokenClient.refresh(
      clientId: configuration.clientId,
      currentGrant: grant,
    );
    if (!refreshed.scopes.containsAll(configuration.scopes)) {
      throw const DiscordOAuthException(
        'Discord returned fewer OAuth scopes than requested.',
      );
    }
    await _vault.write(refreshed);
    return refreshed;
  }

  Future<DiscordOAuthGrant?> _readGrant(
    DiscordOAuthConfiguration configuration,
  ) async {
    var grant = await _vault.read();
    if (grant != null &&
        grant.expiresWithin(const Duration(minutes: 1), _clock())) {
      grant = await _refresh(configuration, grant);
    }
    return grant;
  }

  Future<DiscordOAuthAccount> _loadAccount(DiscordOAuthGrant grant) async {
    final client = _identityFactory(grant.session);
    try {
      final user = await client.getCurrentUser();
      final guilds = grant.scopes.contains('guilds')
          ? await client.getCurrentUserGuilds()
          : const <Map<String, Object?>>[];
      final connections = grant.scopes.contains('connections')
          ? await client.getCurrentUserConnections()
          : const <Map<String, Object?>>[];
      return _accountMapper.map(
        user: user,
        guilds: guilds,
        connections: connections,
      );
    } finally {
      client.close();
    }
  }

  static bool _matchesRedirect(
    Uri uri,
    DiscordOAuthConfiguration configuration,
  ) =>
      uri.scheme == configuration.redirectUri.scheme &&
      uri.host == configuration.redirectUri.host &&
      uri.path == configuration.redirectUri.path &&
      uri.port == configuration.redirectUri.port;

  static bool _constantTimeEquals(String? left, String right) {
    if (left == null || left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < right.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }

  static Future<String> _codeChallenge(String verifier) async {
    final sink = Sha256().newHashSink();
    sink.add(utf8.encode(verifier));
    sink.close();
    final hash = await sink.hash();
    return _token(hash.bytes);
  }

  static String _token(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static List<int> _secureBytes(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(256), growable: false);
  }

  void _completePending(DiscordOAuthAccount account) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(account);
    }
  }

  void _failPending(Object error, [StackTrace? stackTrace]) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(error, stackTrace);
    }
  }

  void _ensureActive() {
    if (_disposed) throw StateError('Discord OAuth service is disposed');
  }

  @override
  Future<void> clear() async {
    _failPending(
      const DiscordOAuthException('Discord authorization was cancelled.'),
    );
    await _vault.clear();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _failPending(
      const DiscordOAuthException('Discord authorization was cancelled.'),
    );
    _tokenClient.close();
  }
}

final class _PendingAuthorization {
  const _PendingAuthorization({
    required this.state,
    required this.verifier,
    required this.completer,
  });

  final String state;
  final String verifier;
  final Completer<DiscordOAuthAccount> completer;
}
