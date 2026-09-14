import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/discord_social_sdk.dart';

final class DiscordSocialSdkGrantCodec {
  const DiscordSocialSdkGrantCodec();

  String encode(DiscordSocialSdkGrant grant) => jsonEncode({
    'version': 1,
    'access_token': grant.accessToken,
    'refresh_token': grant.refreshToken,
    'expires_at': grant.expiresAt.toIso8601String(),
    'scopes': grant.scopes.toList(growable: false),
  });

  DiscordSocialSdkGrant? decode(String encoded) {
    try {
      final payload = jsonDecode(encoded);
      if (payload is! Map || payload['version'] != 1) return null;
      final accessToken = payload['access_token'];
      final refreshToken = payload['refresh_token'];
      final expiresAt = payload['expires_at'];
      final scopes = payload['scopes'];
      if (accessToken is! String ||
          refreshToken is! String ||
          expiresAt is! String ||
          scopes is! List) {
        return null;
      }
      return DiscordSocialSdkGrant(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.parse(expiresAt),
        scopes: scopes.whereType<String>(),
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

final class SecureDiscordSocialSdkGrantVault
    implements DiscordSocialSdkGrantVault {
  const SecureDiscordSocialSdkGrantVault([
    this._storage = const FlutterSecureStorage(),
    this._codec = const DiscordSocialSdkGrantCodec(),
  ]);

  static const _key = 'discord_social_sdk_grant_v1';

  final FlutterSecureStorage _storage;
  final DiscordSocialSdkGrantCodec _codec;

  @override
  Future<DiscordSocialSdkGrant?> read() async {
    final encoded = await _storage.read(key: _key);
    return encoded == null ? null : _codec.decode(encoded);
  }

  @override
  Future<void> write(DiscordSocialSdkGrant grant) =>
      _storage.write(key: _key, value: _codec.encode(grant));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
