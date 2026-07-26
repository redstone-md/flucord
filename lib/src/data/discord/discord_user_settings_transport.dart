/// What Discord answers a settings write with.
final class DiscordSettingsWriteResult {
  const DiscordSettingsWriteResult({this.settings, this.outOfDate = false});

  /// The full merged blob the server now holds, base64 encoded.
  final String? settings;

  /// The server refused the write because it was composed against an older
  /// version of the blob. The client drops the change rather than retrying.
  final bool outOfDate;
}

/// The two calls `/users/@me/settings-proto/{type}` offers.
///
/// Kept apart from the chat API client so the settings store can be driven by
/// a stub: a wrong write here silently replaces a whole group on a live
/// account, which is not something to discover from integration testing.
abstract interface class DiscordUserSettingsTransport {
  /// `GET`, returning the base64 blob or `null` when the account has none.
  Future<String?> readSettingsProto(int type);

  /// `PATCH`, sending a root that carries only the changed groups.
  Future<DiscordSettingsWriteResult> writeSettingsProto({
    required int type,
    required String settings,
  });
}
