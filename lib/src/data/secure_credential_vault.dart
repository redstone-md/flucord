import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/credential_vault.dart';

final class SecureCredentialVault implements CredentialVault {
  const SecureCredentialVault([this._storage = const FlutterSecureStorage()]);

  static const _discordBotTokenKey = 'discord_bot_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readDiscordBotToken() =>
      _storage.read(key: _discordBotTokenKey);

  @override
  Future<void> writeDiscordBotToken(String token) =>
      _storage.write(key: _discordBotTokenKey, value: token.trim());

  @override
  Future<void> clearDiscordBotToken() =>
      _storage.delete(key: _discordBotTokenKey);
}
