import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/discord_oauth.dart';

final class DiscordOAuthGrantCodec {
  const DiscordOAuthGrantCodec();

  String encode(DiscordOAuthGrant grant) => jsonEncode({
    'version': 1,
    'access_token': grant.accessToken,
    'refresh_token': grant.refreshToken,
    'scopes': grant.scopes.toList(growable: false),
    'expires_at': grant.expiresAt.toIso8601String(),
  });

  DiscordOAuthGrant? decode(String encoded) {
    try {
      final payload = jsonDecode(encoded);
      if (payload is! Map || payload['version'] != 1) return null;
      final accessToken = payload['access_token'];
      final refreshToken = payload['refresh_token'];
      final scopes = payload['scopes'];
      final expiresAt = payload['expires_at'];
      if (accessToken is! String ||
          refreshToken is! String ||
          scopes is! List ||
          expiresAt is! String) {
        return null;
      }
      return DiscordOAuthGrant(
        accessToken: accessToken,
        refreshToken: refreshToken,
        scopes: scopes.whereType<String>(),
        expiresAt: DateTime.parse(expiresAt),
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    } on TypeError {
      return null;
    }
  }
}

final class SecureDiscordOAuthGrantVault implements DiscordOAuthGrantVault {
  const SecureDiscordOAuthGrantVault([
    this._storage = const FlutterSecureStorage(),
    this._codec = const DiscordOAuthGrantCodec(),
  ]);

  static const _key = 'discord_oauth_grant_v1';

  final FlutterSecureStorage _storage;
  final DiscordOAuthGrantCodec _codec;

  @override
  Future<DiscordOAuthGrant?> read() async {
    final encoded = await _storage.read(key: _key);
    return encoded == null ? null : _codec.decode(encoded);
  }

  @override
  Future<void> write(DiscordOAuthGrant grant) =>
      _storage.write(key: _key, value: _codec.encode(grant));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
