abstract interface class CredentialVault {
  Future<String?> readDiscordBotToken();

  Future<void> writeDiscordBotToken(String token);

  Future<void> clearDiscordBotToken();
}
