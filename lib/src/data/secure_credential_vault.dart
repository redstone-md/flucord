import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/credential_vault.dart';
import '../domain/discord_session.dart';

final class DiscordSessionCredentialCodec {
  const DiscordSessionCredentialCodec();

  String encode(DiscordAccountSession session) {
    if (session is! DiscordBotSession) {
      throw UnsupportedError(
        'OAuth sessions require an authorization-code refresh store.',
      );
    }
    return jsonEncode({
      'version': 1,
      'kind': session.kind.name,
      'credential': session.transportCredential,
    });
  }

  DiscordAccountSession? decode(String encoded) {
    try {
      final payload = jsonDecode(encoded);
      if (payload is! Map ||
          payload['version'] != 1 ||
          payload['kind'] != DiscordSessionKind.botApplication.name) {
        return null;
      }
      final credential = payload['credential'];
      return credential is String && credential.trim().isNotEmpty
          ? DiscordBotSession(credential)
          : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

final class SecureCredentialVault implements CredentialVault {
  const SecureCredentialVault([
    this._storage = const FlutterSecureStorage(),
    this._codec = const DiscordSessionCredentialCodec(),
  ]);

  static const _discordSessionKey = 'discord_session_v1';
  static const _legacyDiscordBotTokenKey = 'discord_bot_token';

  final FlutterSecureStorage _storage;
  final DiscordSessionCredentialCodec _codec;

  @override
  Future<DiscordAccountSession?> readDiscordSession() async {
    final encoded = await _storage.read(key: _discordSessionKey);
    if (encoded != null) {
      final session = _codec.decode(encoded);
      if (session != null) return session;
    }
    final legacyToken = await _storage.read(key: _legacyDiscordBotTokenKey);
    return legacyToken == null || legacyToken.trim().isEmpty
        ? null
        : DiscordBotSession(legacyToken);
  }

  @override
  Future<void> writeDiscordSession(DiscordAccountSession session) async {
    await _storage.write(
      key: _discordSessionKey,
      value: _codec.encode(session),
    );
    try {
      await _storage.delete(key: _legacyDiscordBotTokenKey);
    } on Object {
      // The versioned record is authoritative; legacy cleanup is best effort.
    }
  }

  @override
  Future<void> clearDiscordSession() async {
    await _storage.delete(key: _discordSessionKey);
    await _storage.delete(key: _legacyDiscordBotTokenKey);
  }
}
