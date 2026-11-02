import 'package:flucord/src/domain/credential_vault.dart';
import 'package:flucord/src/domain/discord_session.dart';

/// A credential vault in memory, which counts how often it is read and written.
final class MemoryCredentialVault implements CredentialVault {
  MemoryCredentialVault({this.session});

  DiscordAccountSession? session;
  int readCalls = 0;
  int writeCalls = 0;

  /// The saved credential, or null when nothing is saved.
  String? get token => session?.transportCredential;

  @override
  Future<void> clearDiscordSession() async => session = null;

  @override
  Future<DiscordAccountSession?> readDiscordSession() async {
    readCalls++;
    return session;
  }

  @override
  Future<void> writeDiscordSession(DiscordAccountSession session) async {
    writeCalls++;
    this.session = session;
  }
}
