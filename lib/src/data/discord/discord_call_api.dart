/// The REST half of a private call: the three routes R08 documents.
///
/// Declared apart from the desktop API client so the call service depends on
/// the three routes it uses rather than on every route the session has, and so
/// a test can drive ringing without standing up an HTTP transport.
abstract interface class DiscordCallApi {
  /// `GET /channels/{id}/call`, reading the response's `ringable` flag.
  Future<bool> isChannelRingable(String channelId);

  /// `POST /channels/{id}/call/ring`. Null [recipients] rings everybody.
  Future<void> ringChannel(
    String channelId, {
    List<String>? recipients,
    required String analyticsLocation,
  });

  /// `POST /channels/{id}/call/stop-ringing`. With no [recipients] this is the
  /// local user declining.
  Future<void> stopRingingChannel(String channelId, {List<String>? recipients});
}
