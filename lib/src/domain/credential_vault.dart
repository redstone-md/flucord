import 'discord_session.dart';

abstract interface class CredentialVault {
  Future<DiscordAccountSession?> readDiscordSession();

  Future<void> writeDiscordSession(DiscordAccountSession session);

  Future<void> clearDiscordSession();
}
